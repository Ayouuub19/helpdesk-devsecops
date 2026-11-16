-- HelpDesk Database Schema

CREATE TABLE IF NOT EXISTS "user" (
    id SERIAL PRIMARY KEY,
    username VARCHAR(80) UNIQUE NOT NULL,
    email VARCHAR(120) UNIQUE NOT NULL,
    password_hash VARCHAR(256) NOT NULL,
    role VARCHAR(20) NOT NULL DEFAULT 'user',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS ticket (
    id SERIAL PRIMARY KEY,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    status VARCHAR(50) DEFAULT 'open',
    priority VARCHAR(20) DEFAULT 'medium',
    user_id INTEGER REFERENCES "user"(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Sample data with fictional information only
INSERT INTO "user" (username, email, password_hash, role) VALUES
('admin', 'admin@helpdesk.local', 'pbkdf2:sha256:...(hashed)', 'admin'),
('alice', 'alice@helpdesk.local', 'pbkdf2:sha256:...(hashed)', 'user'),
('bob', 'bob@helpdesk.local', 'pbkdf2:sha256:...(hashed)', 'user');
