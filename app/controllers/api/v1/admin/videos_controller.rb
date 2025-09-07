class Api::V1::Admin::VideosController < Api::V1::Admin::BaseController
  before_action :authenticate_admin!
  include AdminAuthenticatable

  # GET /api/v1/admin/videos
  def index
    page = params[:page]&.to_i || 1
    limit = params[:limit]&.to_i || 10
    pool = params[:pool]
    sequence = params[:sequence]
    search = params[:search]

    # Start with all videos
    videos_query = Video.includes(:pool, :sequence, :admin, :video_chat_sessions)

    # Apply pool filter
    if pool.present?
      videos_query = videos_query.joins(:pool).where(pools: { name: pool })
    end

    # Apply sequence filter
    if sequence.present?
      videos_query = videos_query.joins(:sequence).where(sequences: { name: sequence })
    end

    # Apply search filter
    if search.present?
      videos_query = videos_query.where(
        "videos.name ILIKE ? OR videos.gender ILIKE ?",
        "%#{search}%", "%#{search}%"
      )
    end

    # Get total count for pagination
    total_count = videos_query.count

    # Apply pagination
    offset = (page - 1) * limit
    videos = videos_query.limit(limit).offset(offset)

    # Use blueprint for serialization
    videos_data = AdminVideosBlueprint.render_as_hash(videos)

    render json: {
      success: true,
      data: {
        data: videos_data,
        total: total_count,
        page: page,
        limit: limit,
        totalPages: (total_count.to_f / limit).ceil
      }
    }
  end

  # GET /api/v1/admin/videos/filters
  def filters
    pools = Pool.pluck(:name).uniq
    sequences = Sequence.pluck(:name).uniq

    render json: {
      success: true,
      data: {
        pools: pools,
        sequences: sequences
      }
    }
  end
end
