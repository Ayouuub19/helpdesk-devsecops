# FAKE_API_KEY = "sk-test-FAKESECRETKEY1234567890abcdef"

from flask import Flask, render_template, request, redirect, url_for, flash, session, jsonify
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager, UserMixin, login_user, logout_user, login_required, current_user
from werkzeug.security import generate_password_hash, check_password_hash
from sqlalchemy import text
from datetime import datetime
import os

app = Flask(__name__)

# INTENTIONAL VULNERABILITY: Weak secret key (for academic demo)
app.config['SECRET_KEY'] = 'dev-secret-change-in-prod'
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///helpdesk.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db = SQLAlchemy(app)
login_manager = LoginManager(app)
login_manager.login_view = 'login'


# ─── Models ───────────────────────────────────────────────────────────────────

class User(UserMixin, db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password_hash = db.Column(db.String(256), nullable=False)
    role = db.Column(db.String(20), default='user', nullable=False)
    tickets = db.relationship('Ticket', backref='owner', lazy=True)

    def set_password(self, password):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password):
        return check_password_hash(self.password_hash, password)


class Ticket(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(200), nullable=False)
    description = db.Column(db.Text, nullable=False)
    status = db.Column(db.String(50), default='open', nullable=False)
    priority = db.Column(db.String(50), default='medium', nullable=False)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)


@login_manager.user_loader
def load_user(user_id):
    return User.query.get(int(user_id))


# ─── DB Init ──────────────────────────────────────────────────────────────────

def init_db():
    db.create_all()

    if User.query.count() == 0:
        admin = User(username='admin', email='admin@helpdesk.local', role='admin')
        admin.set_password('Admin123!')

        alice = User(username='alice', email='alice@helpdesk.local', role='user')
        alice.set_password('Alice123!')

        bob = User(username='bob', email='bob@helpdesk.local', role='user')
        bob.set_password('Bob123!')

        db.session.add_all([admin, alice, bob])
        db.session.commit()

    if Ticket.query.count() == 0:
        tickets = [
            Ticket(
                title='Cannot access email',
                description='My email client stopped working',
                status='open',
                priority='high',
                user_id=2,
            ),
            Ticket(
                title='Printer not working',
                description='The office printer gives error 503',
                status='in_progress',
                priority='medium',
                user_id=3,
            ),
            Ticket(
                title='XSS Demo Ticket',
                description="<img src=x onerror=alert('XSS-VULNERABILITY-DEMO')>",
                status='open',
                priority='low',
                user_id=2,
            ),
            Ticket(
                title='Password reset request',
                description='Need password reset for user charlie',
                status='closed',
                priority='low',
                user_id=1,
            ),
        ]
        db.session.add_all(tickets)
        db.session.commit()


# ─── Routes ───────────────────────────────────────────────────────────────────

@app.route('/')
def index():
    return redirect(url_for('login'))


@app.route('/login', methods=['GET', 'POST'])
def login():
    if current_user.is_authenticated:
        return redirect(url_for('dashboard'))
    if request.method == 'POST':
        username = request.form.get('username', '').strip()
        password = request.form.get('password', '')
        user = User.query.filter_by(username=username).first()
        if user and user.check_password(password):
            login_user(user)
            flash(f'Welcome back, {user.username}!', 'success')
            return redirect(url_for('dashboard'))
        flash('Invalid username or password.', 'danger')
    return render_template('login.html')


@app.route('/logout')
@login_required
def logout():
    logout_user()
    flash('You have been logged out.', 'info')
    return redirect(url_for('login'))


@app.route('/register', methods=['GET', 'POST'])
def register():
    if current_user.is_authenticated:
        return redirect(url_for('dashboard'))
    if request.method == 'POST':
        username = request.form.get('username', '').strip()
        email = request.form.get('email', '').strip()
        password = request.form.get('password', '')
        if User.query.filter_by(username=username).first():
            flash('Username already taken.', 'warning')
        elif User.query.filter_by(email=email).first():
            flash('Email already registered.', 'warning')
        else:
            user = User(username=username, email=email, role='user')
            user.set_password(password)
            db.session.add(user)
            db.session.commit()
            flash('Account created! Please log in.', 'success')
            return redirect(url_for('login'))
    return render_template('register.html')


@app.route('/dashboard')
@login_required
def dashboard():
    if current_user.role == 'admin':
        tickets = Ticket.query.order_by(Ticket.created_at.desc()).all()
    else:
        tickets = Ticket.query.filter_by(user_id=current_user.id).order_by(Ticket.created_at.desc()).all()
    return render_template('dashboard.html', tickets=tickets)


@app.route('/ticket/new', methods=['GET', 'POST'])
@login_required
def new_ticket():
    if request.method == 'POST':
        title = request.form.get('title', '').strip()
        description = request.form.get('description', '').strip()
        priority = request.form.get('priority', 'medium')
        if not title or not description:
            flash('Title and description are required.', 'warning')
        else:
            ticket = Ticket(
                title=title,
                description=description,
                priority=priority,
                status='open',
                user_id=current_user.id,
            )
            db.session.add(ticket)
            db.session.commit()
            flash('Ticket created successfully!', 'success')
            return redirect(url_for('dashboard'))
    return render_template('new_ticket.html')


@app.route('/ticket/<int:ticket_id>')
@login_required
def view_ticket(ticket_id):
    # INTENTIONAL VULNERABILITY: Broken Access Control — no ownership check
    ticket = Ticket.query.get_or_404(ticket_id)
    owner = User.query.get(ticket.user_id)
    return render_template('ticket.html', ticket=ticket, owner=owner)


@app.route('/ticket/<int:ticket_id>/delete')
@login_required
def delete_ticket(ticket_id):
    ticket = Ticket.query.get_or_404(ticket_id)
    if current_user.role != 'admin' and ticket.user_id != current_user.id:
        flash('Not authorised to delete this ticket.', 'danger')
        return redirect(url_for('dashboard'))
    db.session.delete(ticket)
    db.session.commit()
    flash('Ticket deleted.', 'info')
    return redirect(url_for('dashboard'))


@app.route('/admin')
@login_required
def admin_panel():
    if current_user.role != 'admin':
        flash('Admin access required.', 'danger')
        return redirect(url_for('dashboard'))
    users = User.query.all()
    return render_template('admin.html', users=users)


@app.route('/api/tickets/search')
@login_required
def search_tickets():
    q = request.args.get('q', '')
    # INTENTIONAL VULNERABILITY: SQL Injection via string concatenation (academic demo)
    result = db.session.execute(text("SELECT id, title, status FROM ticket WHERE title LIKE '%" + q + "%'"))
    rows = [{'id': row[0], 'title': row[1], 'status': row[2]} for row in result]
    return jsonify(rows)


@app.route('/api/health')
def health():
    return jsonify({'status': 'ok', 'app': 'HelpDesk'})


# ─── Entry point ──────────────────────────────────────────────────────────────

with app.app_context():
    init_db()

if __name__ == '__main__':
    with app.app_context():
        init_db()
    app.run(debug=True, host='0.0.0.0', port=5000)
