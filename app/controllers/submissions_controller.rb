class SubmissionsController < ApplicationController
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
end
