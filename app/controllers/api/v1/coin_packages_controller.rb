class Api::V1::CoinPackagesController < ApplicationController
  # Public endpoint - no authentication required
  skip_before_action :authenticate_user!, if: -> { action_name == 'index' }

  # GET /api/v1/coin_packages
  def index
    coin_packages = CoinPackage.active.order(:price)

    render json: {
      success: true,
      data: {
        coin_packages: coin_packages.map { |package| coin_package_response(package) }
      }
    }
  end

  private

  def coin_package_response(package)
    {
      id: package.id,
      name: package.name,
      price: package.price,
      coins_count: package.coins_count,
      price_per_coin: package.price_per_coin
    }
  end
end
