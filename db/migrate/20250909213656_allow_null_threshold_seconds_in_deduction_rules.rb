class AllowNullThresholdSecondsInDeductionRules < ActiveRecord::Migration[7.2]
  def change
    change_column_null :deduction_rules, :threshold_seconds, true
  end
end
