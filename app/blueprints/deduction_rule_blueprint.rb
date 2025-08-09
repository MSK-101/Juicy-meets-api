class DeductionRuleBlueprint < Blueprinter::Base
  identifier :id

  fields :name, :threshold_seconds, :coins, :active, :created_at, :updated_at
end
