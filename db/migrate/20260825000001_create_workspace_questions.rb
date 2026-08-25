class CreateWorkspaceQuestions < ActiveRecord::Migration[8.1]
  STATUSES = %w[pending answering answered insufficient_context failed].freeze

  def change
    create_table :workspace_questions do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :question, null: false
      t.text :answer
      t.string :status, null: false, default: "pending"
      t.string :answer_model
      t.jsonb :citations, null: false, default: []
      t.string :error_code
      t.string :answer_job_id
      t.integer :answer_job_execution, null: false, default: 0
      t.datetime :answered_at
      t.timestamps
    end

    add_check_constraint :workspace_questions,
                         "status IN (#{STATUSES.map { |status| quote(status) }.join(', ')})",
                         name: "workspace_questions_status_check"
    add_index :workspace_questions, [ :workspace_id, :created_at ]
    add_index :workspace_questions, [ :user_id, :created_at ]
    add_index :workspace_questions, [ :status, :created_at ]
  end
end
