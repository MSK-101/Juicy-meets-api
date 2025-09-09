class AddDeductionTypeToDeductionRules < ActiveRecord::Migration[7.2]
  def change
    add_column :deduction_rules, :deduction_type, :string
  end
end
