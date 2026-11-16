import pytest
from app import app as flask_app, db, init_db


@pytest.fixture
def client():
    flask_app.config['TESTING'] = True
    flask_app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///:memory:'
    flask_app.config['WTF_CSRF_ENABLED'] = False

    with flask_app.app_context():
        db.create_all()
        init_db()
        yield flask_app.test_client()
        db.session.remove()
        db.drop_all()


# ─── Tests ───────────────────────────────────────────────────────────────────

def test_health_check(client):
    response = client.get('/api/health')
    assert response.status_code == 200
    data = response.get_json()
    assert data['status'] == 'ok'
    assert data['app'] == 'HelpDesk'


def test_login_success(client):
    response = client.post(
        '/login',
        data={'username': 'admin', 'password': 'Admin123!'},
        follow_redirects=False,
    )
    assert response.status_code == 302


def test_login_failure(client):
    response = client.post(
        '/login',
        data={'username': 'admin', 'password': 'wrongpassword'},
        follow_redirects=True,
    )
    assert response.status_code == 200
    assert b'Invalid username or password' in response.data


def test_dashboard_requires_auth(client):
    response = client.get('/dashboard', follow_redirects=False)
    assert response.status_code == 302
    assert '/login' in response.headers['Location']


def test_register_and_login(client):
    # Register a new user
    reg_response = client.post(
        '/register',
        data={
            'username': 'testuser',
            'email': 'testuser@example.com',
            'password': 'Test1234!',
        },
        follow_redirects=True,
    )
    assert reg_response.status_code == 200
    assert b'Account created' in reg_response.data

    # Login with new credentials
    login_response = client.post(
        '/login',
        data={'username': 'testuser', 'password': 'Test1234!'},
        follow_redirects=False,
    )
    assert login_response.status_code == 302
