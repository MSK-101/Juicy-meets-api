class Api::V1::SequencesController < Api::V1::Admin::BaseController
  include AdminAuthenticatable
  before_action :authenticate_admin!
  before_action :set_pool
  before_action :set_sequence, only: [:show, :update, :destroy]

  def index
    @sequences = @pool.sequences.ordered
    render json: {
      sequences: @sequences.map do |sequence|
        {
          id: sequence.id,
          name: sequence.name || "Sequence #{sequence.position}",
          video_count: sequence.video_count,
          active: sequence.active,
          position: sequence.position,
          pool_id: sequence.pool_id,
          videos_count: sequence.videos.count,
          content_type: sequence.content_type || []
        }
      end
    }
  end

  def show
    render json: {
      sequence: {
        id: @sequence.id,
        name: @sequence.name || "Sequence #{@sequence.position}",
        video_count: @sequence.video_count,
        active: @sequence.active,
        position: @sequence.position,
        pool_id: @sequence.pool_id,
        content_type: @sequence.content_type || [],
        videos: @sequence.videos.map do |video|
          {
            id: video.id,
            name: video.name,
            gender: video.gender,
            status: video.status
          }
        end
      }
    }
  end

  def create
    @sequence = @pool.sequences.build(sequence_params)
    @sequence.position = @pool.sequences.maximum(:position).to_i + 1

    if @sequence.save
      render json: {
        sequence: {
          id: @sequence.id,
          name: @sequence.name || "Sequence #{@sequence.position}",
          video_count: @sequence.video_count,
          active: @sequence.active,
          position: @sequence.position,
          pool_id: @sequence.pool_id,
          content_type: @sequence.content_type || []
        }
      }, status: :created
    else
      render json: { errors: @sequence.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @sequence.update(sequence_params)
      render json: {
        sequence: {
          id: @sequence.id,
          name: @sequence.name || "Sequence #{@sequence.position}",
          video_count: @sequence.video_count,
          active: @sequence.active,
          position: @sequence.position,
          pool_id: @sequence.pool_id,
          content_type: @sequence.content_type || []
        }
      }
    else
      render json: { errors: @sequence.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @sequence.destroy
    render json: { message: 'Sequence deleted successfully' }
  end

  def reorder
    sequence_ids = params[:sequence_ids]

    if sequence_ids.present?
      sequence_ids.each_with_index do |sequence_id, index|
        sequence = @pool.sequences.find(sequence_id)
        sequence.update(position: index + 1)
      end
      render json: { message: 'Sequences reordered successfully' }
    else
      render json: { error: 'Sequence IDs are required' }, status: :bad_request
    end
  end

  private

  def set_pool
    @pool = Pool.find(params[:pool_id])
  end

  def set_sequence
    @sequence = @pool.sequences.find(params[:id])
  end

  def sequence_params
    params.require(:sequence).permit(:name, :video_count, :active, :pool_id, content_type: [])
  end
end
