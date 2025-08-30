class Api::V1::PoolsController < Api::V1::Admin::BaseController
  include AdminAuthenticatable
  before_action :authenticate_admin!
  before_action :set_pool, only: [:show, :update, :destroy]

  def index
    @pools = Pool.active.ordered
    render json: {
      pools: @pools.map do |pool|
        {
          id: pool.id,
          name: pool.name,
          active: pool.active,
          sequences_count: pool.sequences.count,
          videos_count: pool.videos.count
        }
      end
    }
  end

  def show
    render json: {
      pool: {
        id: @pool.id,
        name: @pool.name,
        active: @pool.active,
        sequences: @pool.sequences.ordered.map do |sequence|
          {
            id: sequence.id,
            name: "Sequence #{sequence.position}",
            video_count: sequence.video_count,
            active: sequence.active,
            position: sequence.position,
            videos_count: sequence.videos.count,
            content_type: sequence.content_type || []
          }
        end
      }
    }
  end

  def create
    @pool = Pool.new(pool_params)

    if @pool.save
      render json: {
        pool: {
          id: @pool.id,
          name: @pool.name,
          active: @pool.active
        }
      }, status: :created
    else
      render json: { errors: @pool.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @pool.update(pool_params)
      render json: {
        pool: {
          id: @pool.id,
          name: @pool.name,
          active: @pool.active
        }
      }
    else
      render json: { errors: @pool.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @pool.destroy
    render json: { message: 'Pool deleted successfully' }
  end

  private

  def set_pool
    @pool = Pool.find(params[:id])
  end

  def pool_params
    params.require(:pool).permit(:name, :active)
  end
end
