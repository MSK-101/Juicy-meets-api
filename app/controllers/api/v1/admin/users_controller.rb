class Api::V1::Admin::UsersController < Api::V1::Admin::BaseController
  before_action :authenticate_admin!
  include AdminAuthenticatable

  # GET /api/v1/admin/users
  def index
    page = params[:page]&.to_i || 1
    limit = params[:limit]&.to_i || 10
    status = params[:status]
    search = params[:search]

    # Start with regular users (not staff) who have transactions
    users_query = User.where(role: :user)
                      # .left_joins(:purchases, :coin_transactions)
                      # .where('purchases.id IS NOT NULL OR coin_transactions.id IS NOT NULL')
                      .distinct
                      .includes(:purchases, :coin_transactions)

    # Apply status filter
    if status.present? && status != 'all'
      case status
      when 'active'
        users_query = users_query.where(user_status: :active)
      when 'banned'
        users_query = users_query.where(user_status: :suspended)
      when 'pending'
        users_query = users_query.where(user_status: :pending)
      end
    end

    # Apply search filter
    if search.present?
      users_query = users_query.where(
        "users.email ILIKE ?",
        "%#{search}%"
      )
    end

    # Get total count for pagination
    total_count = users_query.count

    # Apply pagination
    offset = (page - 1) * limit
    users = users_query.limit(limit).offset(offset)

    # Use blueprint for serialization
    users_data = AdminUsersBlueprint.render_as_hash(users)

    render json: {
      success: true,
      data: {
        data: users_data,
        total: total_count,
        page: page,
        limit: limit,
        totalPages: (total_count.to_f / limit).ceil
      }
    }
  end

  # GET /api/v1/admin/users/stats
  def stats
    # Get regular users (not staff) with transactions
    users_with_transactions = User.where(role: :user)
                                 .left_joins(:purchases, :coin_transactions)
                                 .where('purchases.id IS NOT NULL OR coin_transactions.id IS NOT NULL')
                                 .distinct

    registered = users_with_transactions.count
    inactive = users_with_transactions.where(user_status: :suspended).count
    new_users = users_with_transactions.where('users.created_at >= ?', 7.days.ago).count
    banned = users_with_transactions.where(user_status: :suspended).count

    render json: {
      success: true,
      data: {
        registered: registered,
        inactive: inactive,
        newUsers: new_users,
        banned: banned
      }
    }
  end

end
