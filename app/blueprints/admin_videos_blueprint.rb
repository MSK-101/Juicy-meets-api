class AdminVideosBlueprint < Blueprinter::Base
  identifier :id

  fields :name, :gender, :status, :created_at

  field :uploader do |video|
    video.admin&.email || 'Unknown'
  end

  field :sequence do |video|
    video.sequence&.name || 'N/A'
  end

  field :pool do |video|
    video.pool&.name || 'N/A'
  end

  field :swipeCount do |video|
    video.video_chat_sessions.count
  end

  field :viewCount do |video|
    video.views_in_minutes
  end

  field :uploaded do |video|
    video.created_at.strftime('%m/%d/%Y')
  end
end
