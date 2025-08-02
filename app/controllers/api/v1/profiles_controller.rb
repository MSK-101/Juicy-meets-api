class Api::V1::ProfilesController < ApplicationController
  before_action :authenticate_user!

  # GET /api/v1/profile
  def show
    render json: {
      success: true,
      data: {
        profile: profile_response(current_user)
      }
    }
  end

  # PUT /api/v1/profile
  def update
    if current_user.update(profile_params)
      # Auto-mark profile as completed if all required fields are present
      current_user.complete_profile! if current_user.profile_complete?

      render json: {
        success: true,
        data: {
          profile: profile_response(current_user)
        },
        message: current_user.profile_completed? ? 'Profile completed successfully' : 'Profile updated successfully'
      }
    else
      render json: {
        success: false,
        errors: current_user.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # GET /api/v1/profile/status
  def status
    render json: {
      success: true,
      data: {
        profile_completed: current_user.profile_completed?,
        profile_complete: current_user.profile_complete?,
        required_fields: {
          age: current_user.age.present?,
          gender: current_user.gender.present?,
          interested_in: current_user.interested_in.present?
        },
        missing_fields: missing_profile_fields
      }
    }
  end

  private

  def profile_params
    params.require(:profile).permit(:age, :gender, :interested_in)
  end

  def profile_response(user)
    {
      id: user.id,
      email: user.email,
      provider: user.provider,
      oauth_user: user.oauth_user?,
      # confirmed: user.confirmed?, # Temporarily disabled
      # confirmed_at: user.confirmed_at, # Temporarily disabled
      age: user.age,
      gender: user.gender,
      interested_in: user.interested_in,
      profile_completed: user.profile_completed?,
      profile_complete: user.profile_complete?,
      created_at: user.created_at,
      updated_at: user.updated_at
    }
  end

  def missing_profile_fields
    fields = []
    fields << 'age' unless current_user.age.present?
    fields << 'gender' unless current_user.gender.present?
    fields << 'interested_in' unless current_user.interested_in.present?
    fields
  end
end
