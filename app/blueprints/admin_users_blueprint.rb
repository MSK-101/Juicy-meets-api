class AdminUsersBlueprint < Blueprinter::Base
  identifier :id

  fields :email, :coin_balance, :user_status, :created_at, :last_activity_at

  field :username do |user|
    user.email.split('@').first
  end

  field :coinPurchased do |user|
    user.purchases.completed.sum(:coins_count)
  end

  field :deposits do |user|
    user.purchases.completed.count
  end

  field :totalSpent do |user|
    user.purchases.completed.sum(:price)
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
end
