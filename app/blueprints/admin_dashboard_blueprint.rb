class AdminDashboardBlueprint < Blueprinter::Base
  # Dashboard Stats - nested under 'stats'
  field :stats do
    begin
      total_duration = VideoChatSession.sum(:duration_seconds) || 0
      views_in_minutes = total_duration / 60.0

      total_revenue = Purchase.completed.sum(:price) || 0

      waiting_users = VideoWaitingRoom.waiting.count rescue 0
      active_sessions = VideoChatSession.active.count rescue 0
      active_users = waiting_users + active_sessions

      paying_users_count = begin
        User.joins(:purchases).where(purchases: { payment_status: 'completed' }).distinct.count
      rescue
        0
      end

      {
        views: views_in_minutes.round(2),
        revenue: total_revenue,
        activeUsers: active_users,
        payingUsers: paying_users_count,
        userRetention: calculate_user_retention
      }
    rescue => e
      {
        views: 0,
        revenue: 0,
        activeUsers: 0,
        payingUsers: 0,
        userRetention: 0
      }
    end
  end

  private

  def self.calculate_user_retention
    begin
      total_users = User.where(role: :user).count
      paying_users = User.joins(:purchases).where(purchases: { payment_status: 'completed' }).distinct.count

      return 0 if total_users == 0
      ((paying_users.to_f / total_users) * 100).round(2)
    rescue => e
      0
    end
  end

  # Chart Data (last 6 months)
  field :chartData do
    begin
      (0..5).map do |i|
        month_start = i.months.ago.beginning_of_month
        month_end = i.months.ago.end_of_month

        # Swipes (video chat sessions count)
        swipes = VideoChatSession.where(created_at: month_start..month_end).count rescue 0

        # Video Views (video chat sessions with video_id) - in minutes
        video_duration = VideoChatSession.where(created_at: month_start..month_end)
                                       .where.not(video_id: nil)
                                       .sum(:duration_seconds) || 0
        video_views = (video_duration / 60.0).round(2)

        # Coins Used (total coins deducted)
        coins_used = CoinTransaction.where(created_at: month_start..month_end)
                                   .where(transaction_type: 'debit')
                                   .sum(:amount) || 0

        {
          month: month_start.strftime('%b'),
          swipes: swipes,
          videoViews: video_views,
          coinsUsed: coins_used
        }
      end.reverse
    rescue => e
      []
    end
  end

  # Recent Users (last 5 users with transactions)
  field :recentUsers do
    begin
      User.where(role: :user)
          .left_joins(:purchases, :coin_transactions)
          .where('purchases.id IS NOT NULL OR coin_transactions.id IS NOT NULL')
          .distinct
          .order(created_at: :desc)
          .limit(5)
          .map do |user|
            {
              username: user.email.split('@').first,
              email: user.email,
              coinBalance: user.coin_balance,
              lastLogin: user.last_activity_at&.strftime('%m/%d/%Y') || 'Never'
            }
          end
    rescue => e
      []
    end
  end

  # Top Videos (videos with most views from video chat sessions)
  field :topVideos do
    begin
      Video.joins(:video_chat_sessions)
           .group('videos.id, videos.name')
           .order('SUM(video_chat_sessions.duration_seconds) DESC')
           .limit(5)
           .pluck('videos.name, SUM(video_chat_sessions.duration_seconds)')
           .map do |name, duration_seconds|
             views_in_minutes = (duration_seconds || 0) / 60.0
             { name: name, views: views_in_minutes.round(2) }
           end
    rescue => e
      []
    end
  end
end
