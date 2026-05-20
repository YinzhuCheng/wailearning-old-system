import re

from sqlalchemy import text
from sqlalchemy.exc import OperationalError

from app.attachments import ensure_upload_directories
from app.auth import get_password_hash
from app.config import settings
from app.course_access import sync_course_enrollments
from app.database import Base, SessionLocal, engine
from app.models import Score, Semester, Subject, SystemSetting, User, UserRole


DEFAULT_SEMESTERS = [
    {"name": "2024-春季", "year": 2024},
    {"name": "2024-秋季", "year": 2024},
    {"name": "2025-春季", "year": 2025},
    {"name": "2025-秋季", "year": 2025},
    {"name": "2026-春季", "year": 2026},
    {"name": "2026-秋季", "year": 2026},
]

DEFAULT_SEMESTERS = [
    {"name": "2024-\u6625\u5b63", "year": 2024},
    {"name": "2024-\u79cb\u5b63", "year": 2024},
    {"name": "2025-\u6625\u5b63", "year": 2025},
    {"name": "2025-\u79cb\u5b63", "year": 2025},
    {"name": "2026-\u6625\u5b63", "year": 2026},
    {"name": "2026-\u79cb\u5b63", "year": 2026},
]

DEFAULT_SYSTEM_SETTINGS = [
    ("system_name", "BIMSA-CLASS", "System display name."),
    ("login_background", "", "Custom login background URL."),
    ("system_logo", "", "Custom system logo URL."),
    ("system_intro", "University teaching management platform", "Short introduction shown on the login page."),
    ("copyright", "(c) 2026 BIMSA-CLASS", "Footer copyright text."),
    ("use_bing_background", "true", "Whether the login page should use the daily Bing background."),
]

LEGACY_SYSTEM_SETTING_VALUES = {
    "system_name": {"DD-CLASS", "DD-CLASS 班级管理系统"},
    "copyright": {"(c) 2026 DD-CLASS", "漏 2024 DD-CLASS"},
}


def normalize_legacy_branding(value: str) -> str:
    if not value:
        return value
    return re.sub(r"dd-class", "BIMSA-CLASS", value, flags=re.IGNORECASE)


def ensure_schema_updates() -> None:
    alter_statements = [
        "ALTER TABLE subjects ADD COLUMN IF NOT EXISTS teacher_id INTEGER REFERENCES users(id)",
        "ALTER TABLE subjects ADD COLUMN IF NOT EXISTS class_id INTEGER REFERENCES classes(id)",
        "ALTER TABLE subjects ADD COLUMN IF NOT EXISTS semester_id INTEGER REFERENCES semesters(id)",
        "ALTER TABLE subjects ADD COLUMN IF NOT EXISTS course_type VARCHAR NOT NULL DEFAULT 'required'",
        "ALTER TABLE subjects ADD COLUMN IF NOT EXISTS status VARCHAR NOT NULL DEFAULT 'active'",
        "ALTER TABLE subjects ADD COLUMN IF NOT EXISTS semester VARCHAR",
        "ALTER TABLE subjects ADD COLUMN IF NOT EXISTS weekly_schedule VARCHAR",
        "ALTER TABLE subjects ADD COLUMN IF NOT EXISTS course_start_at TIMESTAMP",
        "ALTER TABLE subjects ADD COLUMN IF NOT EXISTS course_end_at TIMESTAMP",
        "ALTER TABLE subjects ADD COLUMN IF NOT EXISTS course_times TEXT",
        "ALTER TABLE subjects ADD COLUMN IF NOT EXISTS description VARCHAR",
        "ALTER TABLE course_enrollments ADD COLUMN IF NOT EXISTS enrollment_type VARCHAR NOT NULL DEFAULT 'required'",
        """
        CREATE TABLE IF NOT EXISTS course_exam_weights (
            id INTEGER PRIMARY KEY,
            subject_id INTEGER NOT NULL REFERENCES subjects(id),
            exam_type VARCHAR NOT NULL,
            weight FLOAT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            CONSTRAINT uq_course_exam_weight_subject_exam_type UNIQUE(subject_id, exam_type)
        )
        """,
        "ALTER TABLE attendances ADD COLUMN IF NOT EXISTS subject_id INTEGER REFERENCES subjects(id)",
        "ALTER TABLE notifications ADD COLUMN IF NOT EXISTS subject_id INTEGER REFERENCES subjects(id)",
        "ALTER TABLE homeworks ADD COLUMN IF NOT EXISTS attachment_name VARCHAR",
        "ALTER TABLE homeworks ADD COLUMN IF NOT EXISTS attachment_url VARCHAR",
        "ALTER TABLE homework_submissions ADD COLUMN IF NOT EXISTS review_score FLOAT",
        "ALTER TABLE homework_submissions ADD COLUMN IF NOT EXISTS review_comment VARCHAR",
        "ALTER TABLE notifications ADD COLUMN IF NOT EXISTS attachment_name VARCHAR",
        "ALTER TABLE notifications ADD COLUMN IF NOT EXISTS attachment_url VARCHAR",
    ]

    with engine.begin() as connection:
        for statement in alter_statements:
            if engine.dialect.name != "sqlite":
                connection.execute(text(statement))
                continue

            sqlite_statement = (
                statement
                .replace(" ADD COLUMN IF NOT EXISTS ", " ADD COLUMN ")
                .replace(" INTEGER REFERENCES users(id)", " INTEGER")
                .replace(" INTEGER REFERENCES classes(id)", " INTEGER")
                .replace(" INTEGER REFERENCES semesters(id)", " INTEGER")
                .replace(" INTEGER REFERENCES subjects(id)", " INTEGER")
            )
            try:
                connection.execute(text(sqlite_statement))
            except OperationalError as exc:
                if "duplicate column name" not in str(exc).lower():
                    raise

        connection.execute(
            text(
                """
                UPDATE course_enrollments
                SET enrollment_type = CASE
                    WHEN can_remove THEN 'elective'
                    ELSE 'required'
                END
                WHERE enrollment_type IS NULL OR enrollment_type = ''
                """
            )
        )


def seed_default_admin(db) -> None:
    existing_admin = db.query(User).filter(User.username == settings.INIT_ADMIN_USERNAME).first()
    if existing_admin:
        print(f"Admin user '{settings.INIT_ADMIN_USERNAME}' already exists.")
        return

    admin_user = User(
        username=settings.INIT_ADMIN_USERNAME,
        hashed_password=get_password_hash(settings.INIT_ADMIN_PASSWORD),
        real_name=settings.INIT_ADMIN_REAL_NAME,
        role="admin",
        is_active=True,
    )
    db.add(admin_user)
    db.commit()
    print(f"Created bootstrap admin '{settings.INIT_ADMIN_USERNAME}'.")


def seed_default_semesters(db) -> None:
    created = 0
    for semester in DEFAULT_SEMESTERS:
        exists = db.query(Semester).filter(Semester.name == semester["name"]).first()
        if exists:
            continue
        db.add(Semester(name=semester["name"], year=semester["year"], is_active=True))
        created += 1

    if created:
        db.commit()
    print(f"Ensured default semesters. Added {created} item(s).")


def normalize_semester_name(name: str | None) -> str | None:
    if not name:
        return name

    normalized = name.strip()
    match = re.fullmatch(r"(\d{4})-(1|2)", normalized)
    if not match:
        return normalized

    year, term = match.groups()
    return f"{year}-\u6625\u5b63" if term == "1" else f"{year}-\u79cb\u5b63"
    return f"{year}-春季" if term == "1" else f"{year}-秋季"


def normalize_semester_catalog(db) -> None:
    semesters = db.query(Semester).order_by(Semester.created_at.asc(), Semester.id.asc()).all()
    changed = 0

    for semester in semesters:
        normalized_name = normalize_semester_name(semester.name)
        if not normalized_name or normalized_name == semester.name:
            continue

        old_name = semester.name
        existing = db.query(Semester).filter(Semester.name == normalized_name).first()
        if existing and existing.id != semester.id:
            db.query(Subject).filter(Subject.semester_id == semester.id).update(
                {Subject.semester_id: existing.id},
                synchronize_session=False
            )
            db.query(Subject).filter(Subject.semester == old_name).update(
                {Subject.semester: normalized_name},
                synchronize_session=False
            )
            db.query(Score).filter(Score.semester == old_name).update(
                {Score.semester: normalized_name},
                synchronize_session=False
            )
            db.delete(semester)
            changed += 1
            continue

        semester.name = normalized_name
        if normalized_name[:4].isdigit():
            semester.year = int(normalized_name[:4])
        db.query(Subject).filter(Subject.semester == old_name).update(
            {Subject.semester: normalized_name},
            synchronize_session=False
        )
        db.query(Score).filter(Score.semester == old_name).update(
            {Score.semester: normalized_name},
            synchronize_session=False
        )
        changed += 1

    if changed:
        db.commit()
    print(f"Normalized semester catalog. Updated {changed} item(s).")


def sync_subject_semester_links(db) -> None:
    semesters = db.query(Semester).order_by(Semester.year.asc(), Semester.created_at.asc(), Semester.id.asc()).all()
    semesters_by_name = {semester.name: semester for semester in semesters}
    updated = 0

    for course in db.query(Subject).all():
        matched_semester = None

        if course.semester_id:
            matched_semester = next((semester for semester in semesters if semester.id == course.semester_id), None)

        if not matched_semester and course.semester:
            normalized_name = normalize_semester_name(course.semester)
            matched_semester = semesters_by_name.get(normalized_name)

        if not matched_semester:
            continue

        if course.semester_id != matched_semester.id:
            course.semester_id = matched_semester.id
            updated += 1

        if course.semester != matched_semester.name:
            course.semester = matched_semester.name
            updated += 1

    if updated:
        db.commit()
    print(f"Ensured subject semester links. Updated {updated} field(s).")


def seed_default_system_settings(db) -> None:
    created = 0
    updated = 0
    for key, value, description in DEFAULT_SYSTEM_SETTINGS:
        exists = db.query(SystemSetting).filter(SystemSetting.setting_key == key).first()
        if exists:
            normalized_value = normalize_legacy_branding(exists.setting_value)
            if exists.setting_value in LEGACY_SYSTEM_SETTING_VALUES.get(key, set()) or normalized_value != exists.setting_value:
                exists.setting_value = normalized_value if normalized_value else value
                exists.description = description
                updated += 1
            continue
        db.add(
            SystemSetting(
                setting_key=key,
                setting_value=value,
                description=description,
            )
        )
        created += 1

    if created or updated:
        db.commit()
    print(f"Ensured default system settings. Added {created} item(s), updated {updated} item(s).")


def normalize_teacher_class_assignments(db) -> None:
    updated = (
        db.query(User)
        .filter(User.role == UserRole.TEACHER.value, User.class_id.isnot(None))
        .update({User.class_id: None}, synchronize_session=False)
    )
    if updated:
        db.commit()
    print(f"Ensured teacher class assignments. Cleared {updated} item(s).")


def sync_existing_courses(db) -> None:
    synced = 0
    courses = db.query(Subject).filter(Subject.class_id.isnot(None)).all()
    for course in courses:
        synced += sync_course_enrollments(course, db)

    if synced:
        db.commit()
    print(f"Ensured course enrollments. Added {synced} item(s).")


def bootstrap() -> None:
    ensure_upload_directories()
    Base.metadata.create_all(bind=engine)
    ensure_schema_updates()
    Base.metadata.create_all(bind=engine)

    db = SessionLocal()
    try:
        normalize_teacher_class_assignments(db)
        normalize_semester_catalog(db)
        sync_subject_semester_links(db)
        if settings.INIT_DEFAULT_DATA:
            seed_default_admin(db)
            seed_default_semesters(db)
            normalize_semester_catalog(db)
            sync_subject_semester_links(db)
            seed_default_system_settings(db)
            sync_existing_courses(db)
        else:
            print("INIT_DEFAULT_DATA is false. Table creation completed without seed data.")
    finally:
        db.close()


if __name__ == "__main__":
    bootstrap()
