# Pool-Based Video Chat Matching System

## Overview
This system implements a professional video chat experience similar to Omegle with intelligent pool-based matching, staff fallbacks, and video fallbacks. Users are automatically assigned to pools based on their coin balance and purchase history, ensuring seamless tier management.

## Architecture

### Core Components

1. **PoolMatchingService** - Intelligent matching algorithm
2. **VideoChatSession** - Session tracking and analytics
3. **Enhanced VideoWaitingRoom** - Pool-aware queue management
4. **Analytics Controller** - Performance insights

### Pool System
- **Pool A**: Users with coins but NO purchase history (free coins)
- **Pool B**: Users with coins AND purchase history (paid coins)
- **Pool C**: Users with 0 coins (default for new users)

### Sequence Logic
Each pool has sequences containing videos. Users progress through sequences with this logic:

**Sequence Structure:**
- Each sequence has a `video_count` field (e.g., 4 videos)
- Total interactions per sequence = 10 (configurable via `sequence_group_size`)
- Videos are shown when no real users or staff are available

**User Progression:**
- Videos start immediately when no users/staff available (no empty screens)
- Sequence advances automatically after completing all 10 interactions
- Simple and fast matching - no complex counting logic

**Example Sequence:**
- Sequence "First" has video_count = 4
- If no real users available, video starts immediately
- After 10 total interactions, automatically moves to next sequence

## API Endpoints

### Video Chat
```
POST /api/v1/video_chat/join      # Join queue with pool assignment
GET  /api/v1/video_chat/status    # Check match status
POST /api/v1/video_chat/leave     # Leave chat
POST /api/v1/video_chat/swipe     # Swipe to next match
POST /api/v1/video_chat/end_session # End current session
```

### Analytics
```
GET /api/v1/analytics/overview                    # System overview
GET /api/v1/analytics/staff_performance/:staff_id # Staff performance
GET /api/v1/analytics/video_performance/:video_id # Video performance
GET /api/v1/analytics/pool_analytics/:pool_id     # Pool analytics
GET /api/v1/analytics/user_journey/:user_id       # User journey
```

## Matching Algorithm

### Priority Order
1. **Real User Match** - Same pool & sequence
2. **Staff Fallback** - After 2-3 second delay
3. **Video Fallback** - From current sequence
4. **Queue Wait** - If no options available

### Staff Assignment
- Staff are assigned to specific pools and sequences
- Only match with users from their assigned pool
- Automatic busy status when in active chat
- Performance tracking for analytics

### Video Management
- Videos belong to specific pools and sequences
- Sequential progression based on user position
- Gender and interest-based recommendations
- View count and engagement tracking

## Session Tracking

### What Gets Recorded
- User interactions (real users, staff, videos)
- Session duration and completion status
- Pool and sequence progression
- Staff performance metrics
- Video view statistics

### Analytics Insights
- Staff productivity and response times
- Video engagement and completion rates
- Pool distribution and user flow
- User journey patterns

## Database Schema

### New Fields Added
```ruby
# video_waiting_rooms
add_reference :pool
add_reference :sequence
add_column :match_type, :string, default: 'real_user'

# video_chat_sessions (new table)
t.string :session_id
t.references :user, :partner_user, :staff_user, :video, :pool, :sequence
t.string :session_type, :status
t.integer :duration_seconds
t.datetime :started_at, :ended_at
```

## Usage Examples

### Basic Matching Flow
```ruby
# User joins queue
matching_service = PoolMatchingService.new(user_id)
match_result = matching_service.find_match

if match_result[:success]
  session = matching_service.create_session(match_result)
  # Handle match based on type (real_user, staff, video)
end
```

### Swipe to Next Match
```ruby
# User swipes for next match
match_result = matching_service.find_next_match
# Automatically advances sequence if needed
```

### Analytics Queries
```ruby
# Staff performance
stats = VideoChatSession.staff_performance_stats(staff_id, days: 30)

# Video performance
stats = VideoChatSession.video_performance_stats(video_id, days: 30)

# Pool analytics
stats = VideoChatSession.pool_analytics(pool_id, days: 30)
```

## Configuration

### PoolMatchingService Settings
```ruby
PoolMatchingService.configure do |config|
  config.staff_fallback_delay = 3.seconds
  config.max_video_duration = 30.seconds
  config.sequence_group_size = 10
end
```

## Migration Steps

1. **Run migrations**:
   ```bash
   rails db:migrate
   ```

2. **Update existing users** with pool assignments:
   ```ruby
   User.find_each do |user|
     user.update!(pool_id: user.pool&.id)
   end
   ```

3. **Seed staff assignments** for testing:
   ```ruby
   # Create staff assignments in admin panel
   ```

## Testing

### Manual Testing
1. Create users with different coin balances
2. Assign staff to pools
3. Upload videos to sequences
4. Test matching flow with multiple users

### Automated Testing
```ruby
# Test pool assignment
user = User.create!(coin_balance: 100)
assert_equal 'Pool A', user.pool.name

# Test matching service
service = PoolMatchingService.new(user.id)
result = service.find_match
assert result[:success]
```

## Monitoring & Maintenance

### Key Metrics to Watch
- Staff response times
- Video completion rates
- Pool distribution balance
- User satisfaction scores

### Common Issues
- Staff availability bottlenecks
- Video content gaps
- Pool imbalance
- Sequence progression issues

## Future Enhancements

1. **AI-powered matching** based on user preferences
2. **Dynamic pool adjustment** based on load
3. **Advanced analytics** with machine learning
4. **Multi-language support** for global users
5. **Mobile-optimized** swipe gestures

## Support

For technical issues or questions about the pool matching system, refer to:
- Code comments in `PoolMatchingService`
- Model validations and scopes
- API endpoint documentation
- Database schema documentation
