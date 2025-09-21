class Api::V1::Admin::CoinPackagesController < Api::V1::Admin::BaseController
  include AdminAuthenticatable
  # before_action :authenticate_admin!  # Temporarily disabled for testing
  before_action :set_coin_package, only: [:show, :update, :destroy]

  def index
    @coin_packages = CoinPackage.all.order(:sort_order, :price)
    render json: {
      coin_packages: @coin_packages.map do |package|
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
      end
    }
  end

  def show
    render json: {
      coin_package: {
        id: @coin_package.id,
        name: @coin_package.name,
        price: @coin_package.price,
        coins_count: @coin_package.coins_count,
        price_per_coin: @coin_package.price_per_coin,
        description: @coin_package.description,
        active: @coin_package.active,
        sort_order: @coin_package.sort_order,
        created_at: @coin_package.created_at,
        updated_at: @coin_package.updated_at
      }
    }
  end

  def create
    @coin_package = CoinPackage.new(coin_package_params)

    if @coin_package.save
      render json: {
        coin_package: {
          id: @coin_package.id,
          name: @coin_package.name,
          price: @coin_package.price,
          coins_count: @coin_package.coins_count,
          price_per_coin: @coin_package.price_per_coin,
          description: @coin_package.description,
          active: @coin_package.active,
          sort_order: @coin_package.sort_order,
          created_at: @coin_package.created_at,
          updated_at: @coin_package.updated_at
        }
      }, status: :created
    else
      render json: {
        errors: @coin_package.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def update
    if @coin_package.update(coin_package_params)
      render json: {
        coin_package: {
          id: @coin_package.id,
          name: @coin_package.name,
          price: @coin_package.price,
          coins_count: @coin_package.coins_count,
          price_per_coin: @coin_package.price_per_coin,
          description: @coin_package.description,
          active: @coin_package.active,
          sort_order: @coin_package.sort_order,
          created_at: @coin_package.created_at,
          updated_at: @coin_package.updated_at
        }
      }
    else
      render json: {
        errors: @coin_package.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def destroy
    if @coin_package.destroy
      render json: { message: 'Coin package deleted successfully' }
    else
      render json: {
        errors: @coin_package.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  private

  def set_coin_package
    @coin_package = CoinPackage.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Coin package not found' }, status: :not_found
  end

  def coin_package_params
    params.require(:coin_package).permit(:name, :price, :coins_count, :description, :active, :sort_order)
  end
end
