class FieldsController < ApplicationController
  include ReviewStreams

  before_action :set_submission

  # Edit: replace the value with the broker's.
  def update
    error = @submission.edit!(@name, params[:value])
    render_review(@submission, [@name], error: error)
  end

  def approve
    render_review(@submission, [@name], error: @submission.approve!(@name))
  end

  def not_provided
    render_review(@submission, [@name], error: @submission.mark_not_provided!(@name))
  end

  private

  def set_submission
    @submission = Submission.find(params[:submission_id])
    @name = params[:name].to_s
    head :not_found unless Submission::FIELD_NAMES.include?(@name)
  end
end
