# Turbo Stream responses for the review page: replaces the given field rows,
# plus the resolved counter, download button and confirm-all button.
module ReviewStreams
  private

  def render_review(submission, field_names, error: nil)
    streams = field_names.map do |name|
      turbo_stream.replace(helpers.field_frame_id(name),
        partial: "fields/field",
        locals: { submission: submission, field: submission.field(name), error: error })
    end
    streams << turbo_stream.replace("review_status", partial: "submissions/status", locals: { submission: submission })
    streams << turbo_stream.replace("confirm_all", partial: "submissions/confirm_all", locals: { submission: submission })

    respond_to do |format|
      format.turbo_stream { render turbo_stream: streams, status: error ? :unprocessable_entity : :ok }
      format.html do
        flash[:alert] = error if error
        redirect_to submission, status: :see_other
      end
    end
  end
end
