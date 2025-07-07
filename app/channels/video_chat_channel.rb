class VideoChatChannel < ApplicationCable::Channel
  def subscribed
    stream_from "video_chat_#{params[:room]}"
  end

  def receive(data)
    ActionCable.server.broadcast("video_chat_#{params[:room]}", data)
  end

  def unsubscribed
    # No cleanup needed
  end
end
