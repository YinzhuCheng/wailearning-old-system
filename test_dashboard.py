import sys
sys.path.insert(0, 'g:/ddclass')

from app.database import engine, get_db
from app.models import User, Student, Score, Attendance, Class
from app.routers.dashboard import get_dashboard_stats
from app.routers.classes import get_accessible_class_ids
from sqlalchemy.orm import Session
from sqlalchemy import text

# 创建数据库连接
db = next(get_db())

# 创建一个测试用户（模拟登录后的用户）
try:
    test_user = db.query(User).filter(User.username == 'admin').first()
    if not test_user:
        print("未找到 admin 用户")
        sys.exit(1)
    
    print(f"测试用户: {test_user.username}, 角色: {test_user.role}")
    
    # 获取可访问的班级
    class_ids = get_accessible_class_ids(test_user, db)
    print(f"可访问的班级ID: {class_ids}")
    
    # 测试查询
    if class_ids:
        students_count = db.query(Student).filter(Student.class_id.in_(class_ids)).count()
        print(f"学生总数: {students_count}")
    else:
        print("警告: 没有可访问的班级")
    
    # 尝试调用 dashboard API
    try:
        result = get_dashboard_stats(semester='', db=db, current_user=test_user)
        print(f"Dashboard API 调用成功: {result.total_students} 学生")
    except Exception as e:
        print(f"Dashboard API 调用失败: {e}")
        import traceback
        traceback.print_exc()

except Exception as e:
    print(f"测试过程中出错: {e}")
    import traceback
    traceback.print_exc()
finally:
    db.close()
