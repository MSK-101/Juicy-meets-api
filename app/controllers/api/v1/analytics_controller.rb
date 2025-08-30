class Api::V1::AnalyticsController < Api::V1::Admin::BaseController
  include AdminAuthenticatable
  before_action :authenticate_admin!

  # GET /api/v1/analytics/staff_performance/:staff_id
  def staff_performance
    staff_id = params[:staff_id]
    days = params[:days]&.to_i || 30

    stats = VideoChatSession.staff_performance_stats(staff_id, days: days)

    render json: {
      staff_id: staff_id,
      period_days: days,
      stats: stats
    }
  end

  # GET /api/v1/analytics/video_performance/:video_id
  def video_performance
    video_id = params[:video_id]
    days = params[:days]&.to_i || 30

    stats = VideoChatSession.video_performance_stats(video_id, days: days)

    render json: {
      video_id: video_id,
      period_days: days,
      stats: stats
    }
  end

  # GET /api/v1/analytics/pool_analytics/:pool_id
  def pool_analytics
    pool_id = params[:pool_id]
    days = params[:days]&.to_i || 30

    stats = VideoChatSession.pool_analytics(pool_id, days: days)

    render json: {
      pool_id: pool_id,
      period_days: days,
      stats: stats
    }
  end

  # GET /api/v1/analytics/overview
  def overview
    days = params[:days]&.to_i || 30

    total_sessions = VideoChatSession.recent.count
    total_users = VideoChatSession.recent.distinct.count(:user_id)
    total_staff = VideoChatSession.recent.user_to_staff.distinct.count(:staff_user_id)
    total_videos = VideoChatSession.recent.user_to_video.distinct.count(:video_id)

    # Top performing staff
    top_staff = VideoChatSession.recent
                                .user_to_staff
                                .group(:staff_user_id)
                                .order('COUNT(*) DESC')
                                .limit(5)
                                .count

    # Top viewed videos
    top_videos = VideoChatSession.recent
                                 .user_to_video
                                 .group(:video_id)
                                 .order('COUNT(*) DESC')
                                 .limit(5)
                                 .count

    # Pool distribution
    pool_distribution = VideoChatSession.recent
                                       .group(:pool_id)
                                       .count

    render json: {
      period_days: days,
      overview: {
        total_sessions: total_sessions,
        total_users: total_users,
        total_staff: total_staff,
        total_videos: total_videos
      },
      top_performers: {
        staff: top_staff,
        videos: top_videos
      },
      pool_distribution: pool_distribution
    }
  end

  # GET /api/v1/analytics/user_journey/:user_id
  def user_journey
    user_id = params[:user_id]
    days = params[:days]&.to_i || 30

    sessions = VideoChatSession.recent
                               .where(user_id: user_id)
                               .order(:started_at)
                               .includes(:pool, :sequence, :video, :staff_user)

    journey_data = sessions.map do |session|
      {
        session_id: session.session_id,
        session_type: session.session_type,
        started_at: session.started_at,
        ended_at: session.ended_at,
        duration_seconds: session.duration_seconds,
        status: session.status,
        pool: session.pool&.name,
        sequence: session.sequence&.name,
        partner: session.partner_user&.email || session.staff_user&.email || 'Video',
        video_name: session.video&.name
      }
    end

    render json: {
      user_id: user_id,
      period_days: days,
      total_sessions: sessions.count,
      journey: journey_data
    }
  end
end
