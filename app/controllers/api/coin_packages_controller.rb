class Api::CoinPackagesController < ApplicationController
  # before_action :authenticate_user!

  def index
    @coin_packages = CoinPackage.active.ordered
    render json: {
      coin_packages: @coin_packages.map do |package|
        {
          id: package.id,
          name: package.name,
          price: package.price,
          coins_count: package.coins_count,
          price_per_coin: package.price_per_coin,
          description: package.description
        }
      end
    }
  end

  def show
    @coin_package = CoinPackage.active.find(params[:id])
    render json: {
      coin_package: {
        id: @coin_package.id,
        name: @coin_package.name,
        price: @coin_package.price,
        coins_count: @coin_package.coins_count,
        price_per_coin: @coin_package.price_per_coin,
        description: @coin_package.description
      }
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Coin package not found' }, status: :not_found
  end
end
