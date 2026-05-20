from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import desc
from typing import List, Optional
from datetime import datetime, timedelta, timezone
from app.database import get_db
from app.models import Student, Class, Score, Attendance, Notification, User, Homework
from app.auth import get_current_active_user
import secrets

router = APIRouter(prefix="/api/parent", tags=["家长端口"])


def generate_parent_code():
    """生成8位家长码"""
    return secrets.token_hex(4).upper()


@router.get("/verify/{parent_code}")
def verify_parent_code(
    parent_code: str,
    db: Session = Depends(get_db)
):
    """验证家长码是否有效"""
    student = db.query(Student).filter(
        Student.parent_code == parent_code
    ).first()

    if not student:
        return {"valid": False, "message": "家长码无效"}

    if student.parent_code_expires and student.parent_code_expires < datetime.now():
        return {"valid": False, "message": "家长码已过期"}

    class_obj = db.query(Class).filter(Class.id == student.class_id).first()

    return {
        "valid": True,
        "message": "验证成功",
        "student_name": student.name,
        "class_name": class_obj.name if class_obj else None
    }


@router.get("/student/{parent_code}")
def get_student_by_parent_code(
    parent_code: str,
    db: Session = Depends(get_db)
):
    """通过家长码获取学生信息"""
    student = db.query(Student).filter(
        Student.parent_code == parent_code
    ).first()

    if not student:
        raise HTTPException(status_code=404, detail="家长码无效")

    if student.parent_code_expires and student.parent_code_expires < datetime.now():
        raise HTTPException(status_code=403, detail="家长码已过期")

    class_obj = db.query(Class).filter(Class.id == student.class_id).first()

    return {
        "student_id": student.id,
        "student_name": student.name,
        "student_no": student.student_no,
        "class_id": student.class_id,
        "class_name": class_obj.name if class_obj else None,
        "gender": student.gender.value if student.gender else None,
        "parent_code": student.parent_code
    }


@router.get("/scores/{parent_code}")
def get_student_scores_by_parent_code(
    parent_code: str,
    semester: Optional[str] = None,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db)
):
    """通过家长码获取学生成绩"""
    student = db.query(Student).filter(
        Student.parent_code == parent_code
    ).first()

    if not student:
        raise HTTPException(status_code=404, detail="家长码无效")

    if student.parent_code_expires and student.parent_code_expires < datetime.now():
        raise HTTPException(status_code=403, detail="家长码已过期")

    query = db.query(Score).filter(Score.student_id == student.id)

    if semester:
        query = query.filter(Score.semester == semester)

    total = query.count()
    scores = query.order_by(desc(Score.exam_date)).offset((page-1)*page_size).limit(page_size).all()

    return {
        "total": total,
        "student_name": student.name,
        "scores": [
            {
                "id": s.id,
                "subject_name": s.subject.name if s.subject else None,
                "score": s.score,
                "exam_type": s.exam_type,
                "exam_date": s.exam_date,
                "semester": s.semester
            }
            for s in scores
        ]
    }


@router.get("/notifications/{parent_code}")
def get_class_notifications_by_parent_code(
    parent_code: str,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db)
):
    """通过家长码获取班级通知"""
    student = db.query(Student).filter(
        Student.parent_code == parent_code
    ).first()

    if not student:
        raise HTTPException(status_code=404, detail="家长码无效")

    if student.parent_code_expires and student.parent_code_expires < datetime.now():
        raise HTTPException(status_code=403, detail="家长码已过期")

    query = db.query(Notification).filter(
        (Notification.class_id == None) |
        (Notification.class_id == student.class_id)
    )

    total = query.count()
    notifications = query.order_by(
        desc(Notification.is_pinned),
        desc(Notification.created_at)
    ).offset((page-1)*page_size).limit(page_size).all()

    return {
        "total": total,
        "notifications": [
            {
                "id": n.id,
                "title": n.title,
                "content": n.content,
                "priority": n.priority,
                "is_pinned": n.is_pinned,
                "created_at": n.created_at,
                "creator_name": n.creator.real_name if n.creator else None
            }
            for n in notifications
        ]
    }


@router.get("/homework/{parent_code}")
def get_class_homework_by_parent_code(
    parent_code: str,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db)
):
    """通过家长码获取班级作业"""
    student = db.query(Student).filter(
        Student.parent_code == parent_code
    ).first()

    if not student:
        raise HTTPException(status_code=404, detail="家长码无效")

    if student.parent_code_expires and student.parent_code_expires < datetime.now():
        raise HTTPException(status_code=403, detail="家长码已过期")

    query = db.query(Homework).filter(Homework.class_id == student.class_id)

    total = query.count()
    homeworks = query.order_by(desc(Homework.created_at)).offset((page-1)*page_size).limit(page_size).all()

    return {
        "total": total,
        "homeworks": [
            {
                "id": h.id,
                "title": h.title,
                "content": h.content,
                "subject_name": h.subject.name if h.subject else None,
                "due_date": h.due_date,
                "created_at": h.created_at,
                "creator_name": h.creator.real_name if h.creator else None
            }
            for h in homeworks
        ]
    }


@router.get("/stats/{parent_code}")
def get_student_stats_by_parent_code(
    parent_code: str,
    semester: Optional[str] = None,
    db: Session = Depends(get_db)
):
    """通过家长码获取学生统计数据"""
    student = db.query(Student).filter(
        Student.parent_code == parent_code
    ).first()

    if not student:
        raise HTTPException(status_code=404, detail="家长码无效")

    if student.parent_code_expires and student.parent_code_expires < datetime.now():
        raise HTTPException(status_code=403, detail="家长码已过期")

    score_query = db.query(Score).filter(Score.student_id == student.id)
    if semester:
        score_query = score_query.filter(Score.semester == semester)

    scores = score_query.all()
    total_exams = len(scores)
    avg_score = round(sum(s.score for s in scores if s.score) / len([s for s in scores if s.score]), 2) if scores else 0

    attendances = db.query(Attendance).filter(Attendance.student_id == student.id).all()
    total_days = len(attendances)
    present_days = len([a for a in attendances if a.status == 'present'])
    attendance_rate = round(present_days / total_days * 100, 2) if total_days > 0 else 100

    return {
        "student_name": student.name,
        "class_name": student.class_obj.name if student.class_obj else None,
        "semester": semester or "全部",
        "total_exams": total_exams,
        "average_score": avg_score,
        "total_attendance_days": total_days,
        "attendance_rate": attendance_rate
    }


@router.post("/students/{student_id}/generate-code")
def generate_student_parent_code(
    student_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """生成/重置学生家长码（需要教师权限）"""
    if current_user.role not in ['admin', 'class_teacher', 'teacher']:
        raise HTTPException(status_code=403, detail="只有教师可以操作")

    student = db.query(Student).filter(Student.id == student_id).first()
    if not student:
        raise HTTPException(status_code=404, detail="学生不存在")

    if current_user.role != 'admin':
        if current_user.role in ['class_teacher', 'teacher']:
            if current_user.class_id and student.class_id != current_user.class_id:
                raise HTTPException(status_code=403, detail="只能操作自己班级的学生")
        else:
            raise HTTPException(status_code=403, detail="无权操作")

    parent_code = generate_parent_code()

    student.parent_code = parent_code
    student.parent_code_expires = datetime.now() + timedelta(days=365)

    db.commit()

    return {
        "student_id": student.id,
        "student_name": student.name,
        "parent_code": parent_code,
        "expires_at": student.parent_code_expires
    }


@router.post("/students/batch-generate-codes")
def batch_generate_student_parent_codes(
    student_ids: List[int],
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """批量生成学生家长码（需要教师权限）"""
    if current_user.role not in ['admin', 'class_teacher', 'teacher']:
        raise HTTPException(status_code=403, detail="只有教师可以操作")

    results = []

    for student_id in student_ids:
        student = db.query(Student).filter(Student.id == student_id).first()
        if not student:
            continue

        if current_user.role != 'admin':
            if current_user.role in ['class_teacher', 'teacher']:
                if current_user.class_id and student.class_id != current_user.class_id:
                    continue
            else:
                continue

        parent_code = generate_parent_code()
        student.parent_code = parent_code
        student.parent_code_expires = datetime.now() + timedelta(days=365)

        results.append({
            "student_id": student.id,
            "student_name": student.name,
            "parent_code": parent_code
        })

    db.commit()

    return {
        "generated_count": len(results),
        "students": results
    }


@router.delete("/students/{student_id}/revoke-code")
def revoke_student_parent_code(
    student_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """撤销学生家长码（需要教师权限）"""
    if current_user.role not in ['admin', 'class_teacher', 'teacher']:
        raise HTTPException(status_code=403, detail="只有教师可以操作")

    student = db.query(Student).filter(Student.id == student_id).first()
    if not student:
        raise HTTPException(status_code=404, detail="学生不存在")

    if current_user.role != 'admin':
        if current_user.role in ['class_teacher', 'teacher']:
            if current_user.class_id and student.class_id != current_user.class_id:
                raise HTTPException(status_code=403, detail="只能操作自己班级的学生")
        else:
            raise HTTPException(status_code=403, detail="无权操作")

    student.parent_code = None
    student.parent_code_expires = None

    db.commit()

    return {"message": "家长码已撤销"}
