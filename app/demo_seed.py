from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session

from app.auth import get_password_hash
from app.models import (
    Attendance,
    AttendanceStatus,
    Class,
    CourseEnrollment,
    CourseMaterial,
    Gender,
    Homework,
    HomeworkSubmission,
    Notification,
    PointItem,
    PointRecord,
    PointRule,
    Score,
    Semester,
    Student,
    StudentPoint,
    Subject,
    User,
    UserRole,
)


DEMO_STAFF_PASSWORD = "demo123456"
DEMO_STUDENT_PASSWORD = "111111"
DEMO_CLASS_NAME = "旧系统演示班"
DEMO_PARENT_CODES = {
    "oldstu1": "OLDP001A",
    "oldstu2": "OLDP002B",
    "oldstu3": "OLDP003C",
    "oldstu4": "OLDP004D",
}


def _user(db: Session, *, username: str, real_name: str, role: str, password: str, class_id: int | None = None) -> User:
    row = db.query(User).filter(User.username == username).first()
    password_hash = get_password_hash(password)
    if not row:
        row = User(
            username=username,
            hashed_password=password_hash,
            real_name=real_name,
            role=role,
            class_id=class_id,
            is_active=True,
        )
        db.add(row)
        db.flush()
        return row

    row.real_name = real_name
    row.role = role
    row.class_id = class_id
    row.is_active = True
    row.hashed_password = password_hash
    return row


def _ensure_demo_class(db: Session) -> Class:
    row = db.query(Class).filter(Class.name == DEMO_CLASS_NAME).first()
    if row:
        row.grade = 2026
        return row

    row = Class(name=DEMO_CLASS_NAME, grade=2026)
    db.add(row)
    db.flush()
    return row


def _ensure_demo_students(db: Session, *, klass: Class, teacher: User) -> list[Student]:
    specs = [
        ("oldstu1", "旧演示学生一", Gender.MALE, "13800002001", "13900002001", "北京市海淀区演示路 1 号"),
        ("oldstu2", "旧演示学生二", Gender.FEMALE, "13800002002", "13900002002", "北京市海淀区演示路 2 号"),
        ("oldstu3", "旧演示学生三", Gender.MALE, "13800002003", "13900002003", "北京市海淀区演示路 3 号"),
        ("oldstu4", "旧演示学生四", Gender.FEMALE, "13800002004", "13900002004", "北京市海淀区演示路 4 号"),
    ]
    students: list[Student] = []
    expires = datetime.now(timezone.utc) + timedelta(days=365)

    for student_no, name, gender, phone, parent_phone, address in specs:
        _user(
            db,
            username=student_no,
            real_name=name,
            role=UserRole.STUDENT.value,
            password=DEMO_STUDENT_PASSWORD,
            class_id=klass.id,
        )

        row = db.query(Student).filter(Student.class_id == klass.id, Student.student_no == student_no).first()
        if not row:
            row = Student(
                name=name,
                student_no=student_no,
                gender=gender,
                phone=phone,
                parent_phone=parent_phone,
                address=address,
                class_id=klass.id,
                teacher_id=teacher.id,
                parent_code=DEMO_PARENT_CODES[student_no],
                parent_code_expires=expires,
            )
            db.add(row)
            db.flush()
        else:
            row.name = name
            row.gender = gender
            row.phone = phone
            row.parent_phone = parent_phone
            row.address = address
            row.teacher_id = teacher.id
            row.parent_code = DEMO_PARENT_CODES[student_no]
            row.parent_code_expires = row.parent_code_expires or expires
        students.append(row)

    return students


def _ensure_demo_course(db: Session, *, klass: Class, teacher: User) -> Subject:
    semester = (
        db.query(Semester).filter(Semester.name == "2026-春季").first()
        or db.query(Semester).order_by(Semester.year.desc(), Semester.id.desc()).first()
    )
    row = db.query(Subject).filter(Subject.name == "旧系统演示课：数据素养", Subject.class_id == klass.id).first()
    if not row:
        row = Subject(
            name="旧系统演示课：数据素养",
            teacher_id=teacher.id,
            class_id=klass.id,
            semester_id=semester.id if semester else None,
            course_type="required",
            status="active",
            semester=semester.name if semester else "2026-春季",
            weekly_schedule="周二 09:00-10:30；周四 14:00-15:30",
            course_start_at=datetime(2026, 3, 2, 9, 0, tzinfo=timezone.utc),
            course_end_at=datetime(2026, 6, 30, 15, 30, tzinfo=timezone.utc),
            description="旧系统空机部署演示课程，包含学生、成绩、考勤、作业、通知、资料和积分样例。",
        )
        db.add(row)
        db.flush()
    else:
        row.teacher_id = teacher.id
        row.class_id = klass.id
        row.semester_id = semester.id if semester else row.semester_id
        row.semester = semester.name if semester else row.semester
        row.course_type = "required"
        row.status = "active"
        row.description = "旧系统空机部署演示课程，包含学生、成绩、考勤、作业、通知、资料和积分样例。"
    return row


def _ensure_enrollments(db: Session, *, course: Subject, klass: Class, students: list[Student]) -> None:
    for student in students:
        row = (
            db.query(CourseEnrollment)
            .filter(CourseEnrollment.subject_id == course.id, CourseEnrollment.student_id == student.id)
            .first()
        )
        if not row:
            db.add(
                CourseEnrollment(
                    subject_id=course.id,
                    student_id=student.id,
                    class_id=klass.id,
                    enrollment_type="required",
                    can_remove=False,
                )
            )


def _ensure_scores_and_attendance(db: Session, *, course: Subject, klass: Class, students: list[Student]) -> None:
    score_values = [92, 86, 78, 95]
    statuses = [AttendanceStatus.PRESENT, AttendanceStatus.LATE, AttendanceStatus.ABSENT, AttendanceStatus.LEAVE]
    for index, student in enumerate(students):
        score = (
            db.query(Score)
            .filter(Score.student_id == student.id, Score.subject_id == course.id, Score.exam_type == "midterm")
            .first()
        )
        if not score:
            db.add(
                Score(
                    student_id=student.id,
                    subject_id=course.id,
                    class_id=klass.id,
                    score=score_values[index],
                    exam_type="midterm",
                    exam_date=datetime(2026, 4, 20, tzinfo=timezone.utc),
                    semester="2026-春季",
                )
            )
        else:
            score.score = score_values[index]

        attendance = (
            db.query(Attendance)
            .filter(Attendance.student_id == student.id, Attendance.subject_id == course.id)
            .first()
        )
        if not attendance:
            db.add(
                Attendance(
                    student_id=student.id,
                    class_id=klass.id,
                    subject_id=course.id,
                    date=datetime(2026, 4, 22, 9, 0, tzinfo=timezone.utc),
                    status=statuses[index],
                    remark="旧系统演示考勤记录",
                )
            )
        else:
            attendance.status = statuses[index]
            attendance.remark = "旧系统演示考勤记录"


def _ensure_homework_notification_material(db: Session, *, course: Subject, klass: Class, teacher: User, students: list[Student]) -> None:
    homework = db.query(Homework).filter(Homework.subject_id == course.id, Homework.title == "旧系统演示作业：数据观察记录").first()
    if not homework:
        homework = Homework(
            title="旧系统演示作业：数据观察记录",
            content="请用 300 字描述一次课堂数据观察，并列出一个可量化指标。",
            class_id=klass.id,
            subject_id=course.id,
            due_date=datetime.now(timezone.utc) + timedelta(days=7),
            created_by=teacher.id,
        )
        db.add(homework)
        db.flush()
    else:
        homework.content = "请用 300 字描述一次课堂数据观察，并列出一个可量化指标。"

    for student in students[:2]:
        submission = (
            db.query(HomeworkSubmission)
            .filter(HomeworkSubmission.homework_id == homework.id, HomeworkSubmission.student_id == student.id)
            .first()
        )
        if not submission:
            db.add(
                HomeworkSubmission(
                    homework_id=homework.id,
                    student_id=student.id,
                    subject_id=course.id,
                    class_id=klass.id,
                    content=f"{student.name} 的演示提交：本周观察了课堂互动次数，并记录了提问频率。",
                    review_score=88.0 if student.student_no == "oldstu1" else 82.0,
                    review_comment="演示批改：结构完整，可以继续补充数据来源。",
                )
            )

    notification = db.query(Notification).filter(Notification.title == "旧系统演示通知：本周课程安排").first()
    if not notification:
        db.add(
            Notification(
                title="旧系统演示通知：本周课程安排",
                content="本周四进行一次课堂数据观察练习，请携带电脑。",
                priority="high",
                is_pinned=True,
                class_id=klass.id,
                subject_id=course.id,
                created_by=teacher.id,
            )
        )

    material = db.query(CourseMaterial).filter(CourseMaterial.subject_id == course.id, CourseMaterial.title == "旧系统演示资料：课堂数据模板").first()
    if not material:
        db.add(
            CourseMaterial(
                title="旧系统演示资料：课堂数据模板",
                content="字段建议：时间、学生编号、互动类型、持续时间、备注。",
                class_id=klass.id,
                subject_id=course.id,
                created_by=teacher.id,
            )
        )


def _ensure_points(db: Session, *, teacher: User, students: list[Student]) -> None:
    rule = db.query(PointRule).filter(PointRule.name == "旧系统演示：积极提问").first()
    if not rule:
        rule = PointRule(
            name="旧系统演示：积极提问",
            description="课堂主动提问或回答问题。",
            category="课堂表现",
            points=10,
            condition_type="manual",
            condition_value="teacher_award",
            is_active=True,
        )
        db.add(rule)
        db.flush()

    item = db.query(PointItem).filter(PointItem.name == "旧系统演示：免作业券").first()
    if not item:
        db.add(
            PointItem(
                name="旧系统演示：免作业券",
                description="仅用于演示积分商城兑换流程。",
                item_type="coupon",
                points_cost=30,
                stock=20,
                is_active=True,
            )
        )

    for index, student in enumerate(students):
        points = 40 + index * 5
        account = db.query(StudentPoint).filter(StudentPoint.student_id == student.id).first()
        if not account:
            account = StudentPoint(
                student_id=student.id,
                total_points=points,
                available_points=points,
                total_earned=points,
                total_spent=0,
            )
            db.add(account)
            db.flush()
        else:
            account.total_points = max(account.total_points or 0, points)
            account.available_points = max(account.available_points or 0, points)
            account.total_earned = max(account.total_earned or 0, points)

        record = (
            db.query(PointRecord)
            .filter(PointRecord.student_id == student.id, PointRecord.rule_id == rule.id, PointRecord.source_type == "demo_seed")
            .first()
        )
        if not record:
            db.add(
                PointRecord(
                    student_id=student.id,
                    rule_id=rule.id,
                    points=points,
                    balance_after=account.available_points,
                    source_type="demo_seed",
                    description="旧系统演示积分记录",
                    operator_id=teacher.id,
                )
            )


def seed_demo_data(db: Session) -> None:
    """Seed visible old-system demo data for empty Aliyun deployments."""

    klass = _ensure_demo_class(db)
    teacher = _user(
        db,
        username="old_teacher",
        real_name="旧系统演示教师",
        role=UserRole.TEACHER.value,
        password=DEMO_STAFF_PASSWORD,
    )
    _user(
        db,
        username="old_headteacher",
        real_name="旧系统演示班主任",
        role=UserRole.CLASS_TEACHER.value,
        password=DEMO_STAFF_PASSWORD,
        class_id=klass.id,
    )
    students = _ensure_demo_students(db, klass=klass, teacher=teacher)
    course = _ensure_demo_course(db, klass=klass, teacher=teacher)
    _ensure_enrollments(db, course=course, klass=klass, students=students)
    _ensure_scores_and_attendance(db, course=course, klass=klass, students=students)
    _ensure_homework_notification_material(db, course=course, klass=klass, teacher=teacher, students=students)
    _ensure_points(db, teacher=teacher, students=students)
    db.commit()
    print("Old-system demo data seed completed.")
