class Api::V1::UserCoinsController < ApplicationController
  # before_action :authenticate_user!

  def balance
    user_coins = current_user.user_coins || current_user.create_user_coins! if current_user

    render json: {
      balance: 1000|| user_coins.balance,
      total_earned: 1000 || user_coins.total_earned,
      total_spent: 0 || user_coins.total_spent,
      has_coins: true || user_coins.has_coins?,
      last_activity_at: 1000 || user_coins.last_activity_at
    }
  end

  def transactions
    page = params[:page] || 1
    per_page = [params[:per_page] || 20, 100].min

    @transactions = current_user.coin_transactions
                               .includes(:coin_package, :coin_deduction_rule, :user_coin_purchase)
                               .recent
                               .page(page)
                               .per(per_page)

    render json: {
      transactions: @transactions.map do |transaction|
        {
          id: transaction.id,
          transaction_type: transaction.transaction_type,
          amount: transaction.amount,
          balance_after: transaction.balance_after,
          description: transaction.description,
          created_at: transaction.created_at,
          reference: {
            coin_package: transaction.coin_package&.name,
            deduction_rule: transaction.coin_deduction_rule&.name,
            purchase_id: transaction.user_coin_purchase&.id
          }
        }
      end,
      pagination: {
        current_page: @transactions.current_page,
        total_pages: @transactions.total_pages,
        total_count: @transactions.total_count
      }
    }
  end

  def purchase_history
    page = params[:page] || 1
    per_page = [params[:per_page] || 20, 100].min

    @purchases = current_user.user_coin_purchases
                            .includes(:coin_package)
                            .recent
                            .page(page)
                            .per(per_page)

    render json: {
      purchases: @purchases.map do |purchase|
        {
          id: purchase.id,
          coin_package: {
            id: purchase.coin_package.id,
            name: purchase.coin_package.name,
            coins_count: purchase.coin_package.coins_count
          },
          coins_count: purchase.coins_count,
          price: purchase.price,
          payment_status: purchase.payment_status,
          purchased_at: purchase.purchased_at,
          transaction_id: purchase.transaction_id
        }
      end,
      pagination: {
        current_page: @purchases.current_page,
        total_pages: @purchases.total_pages,
        total_count: @purchases.total_count
      }
    }
  end
end
