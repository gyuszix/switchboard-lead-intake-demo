# Runs one channel for a ready submission and prepends the outcome to the
# Quote requests list on the Ready to send page.
class QuoteRequestsController < ApplicationController
  # The PDF exactly as it was emailed to the carrier.
  def document
    quote_request = Submission.find(params[:submission_id]).quote_requests.find(params[:id])
    return head :not_found if quote_request.document.blank?

    send_data quote_request.document, type: "application/pdf", disposition: "inline",
      filename: "sent-to-#{quote_request.carrier.parameterize}-#{quote_request.id}.pdf"
  end

  def create
    submission = Submission.find(params[:submission_id])
    channel = params[:channel].to_s
    return head :not_found unless Channels::CLASSES.key?(channel)

    if (reason = Channels.refusal(submission))
      return render plain: reason, status: :unprocessable_entity
    end

    quote_request = Channels.for(channel).new.call(submission)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove("quote_requests_empty"),
          turbo_stream.prepend("quote_requests", partial: "quote_requests/quote_request", locals: { quote_request: quote_request }),
          turbo_stream.replace("pipeline", partial: "layouts/pipeline", locals: { pipeline: PipelineState.new(page: :ready, submission: submission) })
        ]
      end
      format.html { redirect_to ready_submission_path(submission), status: :see_other }
    end
  end
end
