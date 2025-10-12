class AdminUsersBlueprint < Blueprinter::Base
  identifier :id

  fields :email, :coin_balance, :user_status, :created_at, :last_activity_at, :report_count

  field :username do |user|
    user.email.split('@').first
  end

  field :coinPurchased do |user|
    begin
      user.purchases.completed.sum(:coins_count) || 0
    rescue => e
      0
    end
  end

  field :deposits do |user|
    begin
      user.purchases.completed.count
    rescue => e
      0
    end
  end

  field :totalSpent do |user|
    begin
      user.purchases.completed.sum(:price) || 0
    rescue => e
      0
    end
  end

  field :lastLogin do |user|
    if user.last_activity_at.nil?
      'Never'
    elsif user.last_activity_at > 1.day.ago
      user.last_activity_at.strftime('%I:%M %p')
    elsif user.last_activity_at > 1.week.ago
      user.last_activity_at.strftime('%m/%d/%Y')
    else
      user.last_activity_at.strftime('%m/%d/%Y')
    end
  end

  field :status do |user|
    case user.user_status
    when 'active'
      'active'
    when 'suspended'
      'banned'
    when 'pending'
      'pending'
    else
      'inactive'
    end
  end

  field :blockedUsersCount do |user|
    user.blocked_users&.length || 0
  end

  field :reportCount do |user|
    user.report_count || 0
  end

  field :isBanned do |user|
    user.user_status == 'suspended'
  end

  field :banReason do |user|
    if user.user_status == 'suspended' && user.report_count >= 5
      "Auto-banned after #{user.report_count} reports"
    elsif user.user_status == 'suspended'
      "Manually banned"
    else
      nil
    end
  end
end
