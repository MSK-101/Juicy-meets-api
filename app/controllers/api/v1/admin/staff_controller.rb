class Api::V1::Admin::StaffController < Api::V1::Admin::BaseController
  include AdminAuthenticatable
  before_action :authenticate_admin!

  # GET /api/v1/staff
  def index
    @staff = User.staff.includes(:staff_assignment)
                 .order(:created_at)

    render json: {
      staff: @staff.map do |user|
        {
          id: user.id,
          name: user.email.split('@').first,
          username: user.email.split('@').first,
          email: user.email,
          age: user.age,
          totalActivityTime: format_activity_time(user.total_online_time || 0),
          period: "Today",
          status: user.status,
          assigned_gender: user.gender,
          gender: user.gender,
          assignmentStatus: user.staff_assignment&.status || 'inactive',
          regDate: user.created_at.strftime("%m/%d/%Y"),
          pool: user.staff_assignment&.pool&.name,
          sequence: user.staff_assignment&.sequence&.name,
          lastActivityAt: user.last_activity_at
        }
      end
    }
  end

  # GET /api/v1/staff/:id
  def show
    @user = User.staff.find(params[:id])

    render json: {
      staff: {
        id: @user.id,
        email: @user.email,
        age: @user.age,
        gender: @user.gender,
        role: @user.role,
        status: @user.status,
        last_activity_at: @user.last_activity_at,
        total_online_time: @user.total_online_time,
        pool_id: @user.staff_assignment&.pool_id,
        pool_name: @user.staff_assignment&.pool&.name,
        sequence_id: @user.staff_assignment&.sequence_id,
        sequence_name: @user.staff_assignment&.sequence&.name,
        assignment_status: @user.staff_assignment&.status
      }
    }
  end

  # POST /api/v1/staff
  def create
    # Create user with staff role
    @user = User.new(user_params)
    @user.role = :staff
    @user.password = User.generate_random_password
    @user.confirmed_at = Time.current
    @user.profile_completed = true # Staff profiles are completed by default
    if @user.save
      # Create staff assignment
      @staff_assignment = @user.build_staff_assignment(staff_assignment_params)
      if @staff_assignment.save
        @user.send_password_email
        render json: {
          success: true,
          message: 'Staff member created successfully',
          staff: {
            id: @user.id,
            email: @user.email,
            role: @user.role,
            pool_id: @staff_assignment.pool_id,
            sequence_id: @staff_assignment.sequence_id
          }
        }, status: :created
      else
        @user.destroy
        render json: {
          success: false,
          message: @staff_assignment.errors.full_messages.join(', '),
          errors: @staff_assignment.errors.full_messages
        }, status: :unprocessable_entity
      end
    else
      render json: {
        success: false,
        message: @user.errors.full_messages.join(', '),
        errors: @user.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # PUT /api/v1/staff/:id
  def update
    @user = User.staff.find(params[:id])

    if @user.update(user_params)
      if @user.staff_assignment
        @user.staff_assignment.update(staff_assignment_params)
      else
        @user.create_staff_assignment(staff_assignment_params)
      end

      render json: {
        success: true,
        message: 'Staff member updated successfully'
      }
    else
      render json: {
        success: false,
        message: 'Failed to update staff member',
        errors: @user.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/staff/:id
  def destroy
    @user = User.staff.find(params[:id])

    if @user.destroy
      render json: {
        success: true,
        message: 'Staff member deleted successfully'
      }
    else
      render json: {
        success: false,
        message: 'Failed to delete staff member',
        errors: @user.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # GET /api/v1/staff/available
  def available
    pool_id = params[:pool_id]

    @available_staff = User.available_staff
                          .joins(:staff_assignment)
                          .where(staff_assignments: { status: 'active' })

    @available_staff = @available_staff.where(staff_assignments: { pool_id: pool_id }) if pool_id

    render json: {
      available_staff: @available_staff.map do |user|
        {
          id: user.id,
          email: user.email,
          pool_id: user.staff_assignment&.pool_id,
          sequence_id: user.staff_assignment&.sequence_id,
          last_activity_at: user.last_activity_at
        }
      end
    }
  end

  private

  def user_params
    params.require(:user).permit(:email, :age, :gender)
  end

  def staff_assignment_params
    params.require(:staff_assignment).permit(:pool_id, :sequence_id, :status)
  end

  def format_activity_time(seconds)
    hours = seconds / 3600
    minutes = (seconds % 3600) / 60

    if hours > 0
      "#{hours}h#{minutes}m"
    else
      "#{minutes}m"
    end
  end
end
