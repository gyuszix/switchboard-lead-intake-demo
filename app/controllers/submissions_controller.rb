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

  # The gate: no PDF until every field is resolved, whatever the UI shows.
  def pdf
    submission = Submission.find(params[:id])
    unless submission.all_resolved?
      return render plain: "Every field must be resolved before the PDF can be downloaded.",
                    status: :unprocessable_entity
    end

    send_data SubmissionPdf.new(submission).render,
      filename: "commercial-insurance-application-#{submission.id}.pdf",
      type: "application/pdf", disposition: "attachment"
  end
end
