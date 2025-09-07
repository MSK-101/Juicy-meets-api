class AdminDashboardBlueprint < Blueprinter::Base
  # Dashboard Stats - nested under 'stats'
  field :stats do
    {
      views: (VideoChatSession.sum(:duration_seconds) || 0) / 60.0, # Convert seconds to minutes
      revenue: Purchase.completed.sum(:price) || 0,
      activeUsers: VideoWaitingRoom.waiting.count + VideoChatSession.active.count,
      payingUsers: User.joins(:purchases).where(purchases: { payment_status: 'completed' }).distinct.count,
      userRetention: calculate_user_retention
    }
  end

  private

  def self.calculate_user_retention
    total_users = User.where(role: :user).count
    paying_users = User.joins(:purchases).where(purchases: { payment_status: 'completed' }).distinct.count

    return 0 if total_users == 0
    ((paying_users.to_f / total_users) * 100).round(2)
  end

  # Chart Data (last 6 months)
  field :chartData do
    (0..5).map do |i|
      month_start = i.months.ago.beginning_of_month
      month_end = i.months.ago.end_of_month

      # Swipes (video chat sessions count)
      swipes = VideoChatSession.where(created_at: month_start..month_end).count

      # Video Views (video chat sessions with video_id) - in minutes
      video_views = (VideoChatSession.where(created_at: month_start..month_end)
                                   .where.not(video_id: nil)
                                   .sum(:duration_seconds) || 0) / 60.0

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
  end

  # Recent Users (last 5 users with transactions)
  field :recentUsers do
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
  end

  # Top Videos (videos with most views from video chat sessions)
  field :topVideos do
    Video.joins(:video_chat_sessions)
         .group('videos.id, videos.name')
         .order('SUM(video_chat_sessions.duration_seconds) DESC')
         .limit(5)
         .pluck('videos.name, SUM(video_chat_sessions.duration_seconds)')
         .map do |name, duration_seconds|
           views_in_minutes = (duration_seconds || 0) / 60.0
           { name: name, views: views_in_minutes.round(2) }
         end
  end
end
