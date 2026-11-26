class SubmissionsController < ApplicationController
  include ReviewStreams

  def new
    sample = Sample.all.find { _1[:key] == params[:sample] }
    @transcript = sample&.dig(:transcript).to_s
  end

  def create
    @transcript = params[:transcript].to_s
    if @transcript.blank?
      @error = "Paste a transcript first."
      return render :new, status: :unprocessable_entity
    end

    result = Extractor.new.call(@transcript)
    submission = Submission.create!(
      transcript: @transcript,
      fields: FieldChecker.new(@transcript).categorise(result.fields),
      used_fixtures: result.used_fixtures
    )
    redirect_to submission
  end

  def show
    @submission = Submission.find(params[:id])
  end

  def confirm_all
    submission = Submission.find(params[:id])
    submission.confirm_all_verified!
    render_review(submission, submission.verified_fields.map { _1["name"] })
  end

  # Build the submission JSON from the approved values, then validate it.
  # Same gate as the review: nothing is built until every field is resolved.
  def build
    @submission = Submission.find(params[:id])
    unless @submission.all_resolved?
      return render plain: "Every field must be resolved before the submission can be built.",
                    status: :unprocessable_entity
    end

    @build_errors = @submission.build_submission!
    if @build_errors.empty?
      redirect_to ready_submission_path(@submission), status: :see_other
    else
      render :show, status: :unprocessable_entity
    end
  end

  def ready
    @submission = Submission.find(params[:id])
    redirect_to @submission unless @submission.ready?
  end
end
