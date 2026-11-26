class AddSubmissionJsonToSubmissions < ActiveRecord::Migration[8.1]
  def change
    add_column :submissions, :submission_json, :json
    add_column :submissions, :ready_at, :datetime
  end
end
