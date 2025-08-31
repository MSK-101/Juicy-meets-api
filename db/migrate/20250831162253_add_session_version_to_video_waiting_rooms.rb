class AddSessionVersionToVideoWaitingRooms < ActiveRecord::Migration[7.2]
  def change
    add_column :video_waiting_rooms, :session_version, :string
  end
end
