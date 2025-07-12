class Api::Admin::DashboardController < ApplicationController
  # before_action :authenticate_user!

  def index
    # Get basic statistics
    total_users = User.count
    total_packages = CoinPackage.count
    total_rules = CoinDeductionRule.count
    total_purchases = UserCoinPurchase.completed.count
    total_transactions = CoinTransaction.count

    # Get recent activity
    recent_purchases = UserCoinPurchase.includes(:user, :coin_package)
                                     .completed
                                     .order(purchased_at: :desc)
                                     .limit(10)

    recent_transactions = CoinTransaction.includes(:user)
                                       .order(created_at: :desc)
                                       .limit(10)

    # Get revenue statistics
    total_revenue = UserCoinPurchase.completed.sum(:price)
    monthly_revenue = UserCoinPurchase.completed
                                     .where('purchased_at >= ?', 1.month.ago)
                                     .sum(:price)

    # Get coin statistics
    total_coins_purchased = UserCoinPurchase.completed.sum(:coins_count)
    total_coins_spent = CoinTransaction.debits.sum(:amount).abs

    render json: {
      statistics: {
        total_users: total_users,
        total_packages: total_packages,
        total_rules: total_rules,
        total_purchases: total_purchases,
        total_transactions: total_transactions,
        total_revenue: total_revenue,
        monthly_revenue: monthly_revenue,
        total_coins_purchased: total_coins_purchased,
        total_coins_spent: total_coins_spent
      },
      recent_purchases: recent_purchases.map do |purchase|
        {
          id: purchase.id,
          user_email: purchase.user.email,
          package_name: purchase.coin_package.name,
          coins_count: purchase.coins_count,
          price: purchase.price,
          purchased_at: purchase.purchased_at
        }
      end,
      recent_transactions: recent_transactions.map do |transaction|
        {
          id: transaction.id,
          user_email: transaction.user.email,
          transaction_type: transaction.transaction_type,
          amount: transaction.amount,
          description: transaction.description,
          created_at: transaction.created_at
        }
      end
    }
  end
end
