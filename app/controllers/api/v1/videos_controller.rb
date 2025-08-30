class Api::V1::VideosController < Api::V1::Admin::BaseController
  include AdminAuthenticatable
  before_action :authenticate_admin!, except: [:show_public, :stream_video]
  before_action :set_video, only: [:show, :update, :destroy, :show_public, :stream_video]

  # GET /api/v1/videos
  def index
    videos = Video.includes(:pool, :sequence, :admin)
                  .order(created_at: :desc)
                  .page(params[:page])
                  .per(params[:per_page] || 10)

    # Apply filters
    videos = videos.where(pool_id: params[:pool_id]) if params[:pool_id].present?
    videos = videos.where(sequence_id: params[:sequence_id]) if params[:sequence_id].present?
    videos = videos.where(gender: params[:gender]) if params[:gender].present?
    videos = videos.where(status: params[:status]) if params[:status].present?
    videos = videos.where("name ILIKE ?", "%#{params[:search]}%") if params[:search].present?

    render json: {
      success: true,
      data: {
        videos: videos.map { |video| video_response(video) },
        pagination: {
          current_page: videos.current_page,
          total_pages: videos.total_pages,
          total_count: videos.total_count,
          per_page: videos.limit_value
        }
      }
    }
  end

  # GET /api/v1/videos/:id (Admin only)
  def show
    render json: {
      success: true,
      data: {
        video: video_response(@video)
      }
    }
  end

  # GET /api/v1/videos/:id/public (Public access for video chat)
  def show_public
    render json: {
      success: true,
      data: {
        video: {
          id: @video.id,
          name: @video.name,
          gender: @video.gender,
          status: @video.status,
          video_file_url: @video.video_file.attached? ? @video.video_file.url : nil
        }
      }
    }
  end

    # GET /api/v1/videos/:id/stream (Stream video with CORS headers)
  def stream_video
    unless @video.video_file.attached?
      render json: { error: 'Video file not found' }, status: :not_found
      return
    end

    # Set CORS headers
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET, OPTIONS'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type'
    response.headers['Content-Type'] = @video.video_file.content_type

    # Stream the video content directly
    response.headers['Content-Length'] = @video.video_file.byte_size
    response.headers['Accept-Ranges'] = 'bytes'

    # Stream the video in chunks
    @video.video_file.open do |file|
      while (chunk = file.read(8192))
        response.stream.write(chunk)
      end
    ensure
      response.stream.close
    end
  end

  # OPTIONS /api/v1/videos/:id/stream (Handle CORS preflight)
  def stream_video_options
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET, OPTIONS'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type'
    response.headers['Access-Control-Max-Age'] = '86400'

    head :ok
  end

  # POST /api/v1/videos
  def create
    @video = Video.new(video_params)
    @video.admin = current_admin

    if @video.save
      render json: {
        success: true,
        message: 'Video created successfully',
        data: {
          video: video_response(@video)
        }
      }, status: :created
    else
      render json: {
        success: false,
        message: 'Failed to create video',
        errors: @video.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # PUT /api/v1/videos/:id
  def update
    if @video.update(video_params)
      render json: {
        success: true,
        message: 'Video updated successfully',
        data: {
          video: video_response(@video)
        }
      }
    else
      render json: {
        success: false,
        message: 'Failed to update video',
        errors: @video.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/videos/:id
  def destroy
    @video.destroy
    render json: {
      success: true,
      message: 'Video deleted successfully'
    }
  end

  # GET /api/v1/videos/filters
  def filters
    render json: {
      success: true,
      data: {
        pools: Pool.active.map { |pool| { id: pool.id, name: pool.name } },
        genders: Video.genders.keys.map { |gender| { value: gender, label: gender.humanize } },
        statuses: Video.statuses.keys.map { |status| { value: status, label: status.humanize } }
      }
    }
  end

  private

  def set_video
    @video = Video.find(params[:id])
  end

  def video_params
    params.require(:video).permit(:name, :gender, :status, :pool_id, :sequence_id, :video_file)
  end

  def video_response(video)
    {
      id: video.id,
      name: video.name,
      gender: video.gender,
      status: video.status,
      pool: {
        id: video.pool.id,
        name: video.pool.name
      },
      sequence: {
        id: video.sequence.id,
        name: video.sequence.name || "Sequence #{video.sequence.position}",
        position: video.sequence.position,
        video_count: video.sequence.video_count,
        content_type: video.sequence.content_type || []
      },
      admin: {
        id: video.admin.id,
        email: video.admin.email,
        display_name: video.admin.display_name
      },
      video_file_url: video.video_file.attached? ? video.video_file.url : nil,
      created_at: video.created_at,
      updated_at: video.updated_at
    }
  end
end
