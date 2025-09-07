class Api::V1::Admin::MonetizationController < ApplicationController
  # before_action :authenticate_user!

  def index
    date_range = params[:date_range] || 'today'
    date_filter = build_date_filter(date_range)

    # Get coin packages
    coin_packages = CoinPackage.all.order(:sort_order, :price)

    # Get transactions within date range
    transactions = Purchase.includes(:user, :coin_package)
                          .where(created_at: date_filter)
                          .order(created_at: :desc)
                          .limit(50)

    # Calculate statistics
    stats = calculate_monetization_stats(date_filter)

    # Generate chart data
    chart_data = generate_chart_data(date_filter)

    render json: {
      stats: stats,
      coin_packages: coin_packages.map do |package|
        {
          id: package.id,
          name: package.name,
          price: package.price,
          coins_count: package.coins_count,
          price_per_coin: package.price_per_coin,
          description: package.description,
          active: package.active,
          sort_order: package.sort_order,
          created_at: package.created_at,
          updated_at: package.updated_at
        }
      end,
      transactions: transactions.map do |transaction|
        {
          id: transaction.id,
          user_email: transaction.user.email,
          package_name: transaction.coin_package.name,
          coins_count: transaction.coins_count,
          price: transaction.price,
          purchased_at: transaction.purchased_at,
          payment_status: transaction.payment_status
        }
      end,
      chart_data: chart_data
    }
  end

  def transactions
    date_range = params[:date_range] || 'today'
    date_filter = build_date_filter(date_range)

    transactions = Purchase.includes(:user, :coin_package)
                          .where(created_at: date_filter)
                          .order(created_at: :desc)

    render json: {
      transactions: transactions.map do |transaction|
        {
          id: transaction.id,
          user_email: transaction.user.email,
          package_name: transaction.coin_package.name,
          coins_count: transaction.coins_count,
          price: transaction.price,
          purchased_at: transaction.purchased_at,
          payment_status: transaction.payment_status
        }
      end
    }
  end

  def stats
    date_range = params[:date_range] || 'today'
    date_filter = build_date_filter(date_range)

    stats = calculate_monetization_stats(date_filter)

    render json: {
      stats: stats
    }
  end

  private

  def build_date_filter(date_range)
    case date_range
    when 'today'
      Date.current.beginning_of_day..Date.current.end_of_day
    when 'week'
      1.week.ago..Time.current
    when 'month'
      1.month.ago..Time.current
    when 'year'
      1.year.ago..Time.current
    else
      Date.current.beginning_of_day..Date.current.end_of_day
    end
  end

  def calculate_monetization_stats(date_filter)
    # Revenue calculations
    total_revenue = Purchase.completed.where(created_at: date_filter).sum(:price)
    monthly_revenue = Purchase.completed.where(created_at: 1.month.ago..Time.current).sum(:price)

    # Package statistics
    total_packages = CoinPackage.count
    total_purchases = Purchase.completed.where(created_at: date_filter).count
    total_transactions = CoinTransaction.where(created_at: date_filter).count

    # Most popular package
    most_popular = Purchase.completed
                          .joins(:coin_package)
                          .where(created_at: date_filter)
                          .group('coin_packages.name')
                          .count
                          .max_by { |_, count| count }

    most_popular_package = most_popular ? most_popular[0] : nil

    # Revenue per package
    revenue_per_package = total_packages > 0 ? (total_revenue / total_packages).round(2) : 0

    {
      total_revenue: total_revenue,
      monthly_revenue: monthly_revenue,
      total_packages: total_packages,
      total_purchases: total_purchases,
      total_transactions: total_transactions,
      most_popular_package: most_popular_package,
      revenue_per_package: revenue_per_package
    }
  end

  def generate_chart_data(date_filter)
    # Get revenue and sales data by package
    package_stats = Purchase.completed
                           .joins(:coin_package)
                           .where(created_at: date_filter)
                           .group('coin_packages.name')
                           .group('coin_packages.coins_count')
                           .sum(:price)

    package_sales = Purchase.completed
                           .joins(:coin_package)
                           .where(created_at: date_filter)
                           .group('coin_packages.name')
                           .count

    # Combine data for chart
    package_stats.map do |(name, coins_count), revenue|
      {
        name: "#{name} (#{coins_count} coins)",
        revenue: revenue,
        sales: package_sales[[name, coins_count]] || 0
      }
    end.sort_by { |item| -item[:revenue] }
  end
end
