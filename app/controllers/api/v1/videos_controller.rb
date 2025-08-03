class Api::V1::VideosController < ApplicationController
  skip_before_action :authenticate_user!
  include AdminAuthenticatable
  before_action :set_video, only: [:show, :update, :destroy]

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

  # GET /api/v1/videos/:id
  def show
    render json: {
      success: true,
      data: {
        video: video_response(@video)
      }
    }
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
        video_count: video.sequence.video_count
      },
      admin: {
        id: video.admin.id,
        email: video.admin.email,
        display_name: video.admin.display_name
      },
      video_file_url: video.video_file.attached? ? rails_blob_url(video.video_file) : nil,
      created_at: video.created_at,
      updated_at: video.updated_at
    }
  end
end
