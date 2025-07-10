# Rails Backend Setup Guide

## Environment Variables

The backend uses Rails' default `secret_key_base` for JWT tokens, so no additional environment variables are needed for basic functionality.

## Database Setup

1. **Install dependencies:**
   ```bash
   bundle install
   ```

2. **Setup database:**
   ```bash
   rails db:create
   rails db:migrate
   rails db:seed  # if you have seed data
   ```

3. **Start the server:**
   ```bash
   rails server -p 3000
   ```

## API Endpoints

The backend provides these API endpoints:

### Authentication
- `POST /api/v1/login` - User login
- `DELETE /api/v1/logout` - User logout
- `GET /api/v1/auth/providers` - Available auth providers
- `GET /api/v1/auth/oauth_urls` - OAuth URLs

### User Management
- `POST /api/v1/users` - Create user
- `GET /api/v1/users/me` - Get current user
- `GET /api/v1/users/:id` - Get user by ID

### Profile Management
- `GET /api/v1/profile` - Get user profile
- `PUT /api/v1/profile` - Update user profile
- `GET /api/v1/profile/status` - Get profile status

### Email Confirmation
- `POST /api/v1/confirmation/confirm` - Confirm email
- `POST /api/v1/confirmation/resend` - Resend confirmation
- `POST /api/v1/confirmation/send_email` - Send confirmation email

### OAuth
- `GET /auth/google_oauth2` - Google OAuth login
- `GET /auth/:provider/callback` - OAuth callback

## CORS Configuration

The backend is configured to allow requests from:
- `http://localhost:3001`
- `http://127.0.0.1:3001`
- `https://localhost:3001`
- `https://127.0.0.1:3001`

## Features

✅ **User Authentication** - Devise with JWT
✅ **OAuth Integration** - Google OAuth2
✅ **Email Confirmation** - Devise confirmable
✅ **Profile Management** - User profiles with age/gender
✅ **CORS Support** - Cross-origin requests
✅ **API-only** - No views, just JSON API

## No ActionCable

The backend no longer uses ActionCable since video chat signaling is handled by PubNub on the frontend.
