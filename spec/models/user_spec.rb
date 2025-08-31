require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'sequence management' do
    let(:user) { create(:user) }
    let(:pool) { create(:pool, name: 'Test Pool') }
    let(:sequence1) { create(:sequence, pool: pool, name: 'Sequence 1', position: 1, video_count: 3) }
    let(:sequence2) { create(:sequence, pool: pool, name: 'Sequence 2', position: 2, video_count: 2) }

    before do
      user.update!(
        pool_id: pool.id,
        sequence_id: sequence1.id,
        videos_watched_in_current_sequence: 0,
        sequence_total_videos: sequence1.video_count
      )
    end

    describe '#current_sequence_info' do
      it 'returns current sequence information' do
        info = user.current_sequence_info

        expect(info).to include(
          sequence_id: sequence1.id,
          sequence_name: sequence1.name,
          sequence_position: 1,
          videos_watched: 0,
          total_videos: 3
        )
        expect(info[:progress_percentage]).to eq(0.0)
      end
    end

    describe '#calculate_progress_percentage' do
      it 'calculates progress correctly' do
        user.update!(videos_watched_in_current_sequence: 2)

        expect(user.calculate_progress_percentage).to eq(66.67)
      end

      it 'returns 0 when no videos watched' do
        expect(user.calculate_progress_percentage).to eq(0.0)
      end
    end

    describe '#ready_for_next_sequence?' do
      it 'returns true when video count threshold is reached' do
        user.update!(videos_watched_in_current_sequence: 3)

        expect(user.ready_for_next_sequence?).to be true
      end

      it 'returns false when video count threshold is not reached' do
        user.update!(videos_watched_in_current_sequence: 2)

        expect(user.ready_for_next_sequence?).to be false
      end
    end

    describe '#reset_video_count_for_new_sequence' do
      it 'resets video count to 0' do
        user.update!(videos_watched_in_current_sequence: 3)

        user.reset_video_count_for_new_sequence

        expect(user.reload.videos_watched_in_current_sequence).to eq(0)
      end
    end

    describe '#update_sequence_info' do
      it 'updates sequence information and resets video count' do
        user.update_sequence_info(sequence2.id, sequence2.video_count)

        expect(user.reload.sequence_id).to eq(sequence2.id)
        expect(user.sequence_total_videos).to eq(sequence2.video_count)
        expect(user.videos_watched_in_current_sequence).to eq(0)
      end
    end
  end
end
