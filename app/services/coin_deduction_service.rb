class CoinDeductionService
  # Global rule: deduct 1 coin when users connect
  INITIAL_CONNECTION_COST = 1

  # Simple global variable to toggle initial connection deduction
  # Set this to false to disable initial connection deduction
  INITIAL_CONNECTION_ENABLED = true

  # Minimum coin balance - set to 0 to allow complete deduction
  MINIMUM_COIN_BALANCE = 0

  def self.deduct_initial_connection_cost(user_id)
    # Check if initial connection deduction is enabled
    return { success: true, deducted: 0, new_balance: User.find(user_id).coin_balance } unless INITIAL_CONNECTION_ENABLED

    user = User.find(user_id)

    # Ensure user has at least the minimum coin balance after deduction
    if user.coin_balance > INITIAL_CONNECTION_COST + MINIMUM_COIN_BALANCE
      user.update!(coin_balance: user.coin_balance - INITIAL_CONNECTION_COST)
      return { success: true, deducted: INITIAL_CONNECTION_COST, new_balance: user.coin_balance }
    else
      return { success: false, error: 'Insufficient coins for connection' }
    end
  rescue => e
    return { success: false, error: e.message }
  end

  def self.apply_duration_based_deductions(user_id, chat_duration_seconds)
    user = User.find(user_id)

    # Early exit if user has no coins - avoid processing rules entirely
    if user.coin_balance <= MINIMUM_COIN_BALANCE
      return {
        success: true,
        deducted: 0,
        new_balance: user.coin_balance,
        applied_rules: [],
        chat_duration: chat_duration_seconds,
        no_coins: true # Flag to indicate zero balance
      }
    end

    active_rules = DeductionRule.active.duration_based.ordered
    total_deducted = 0
    applied_rules = []

    active_rules.each do |rule|
      # Check if chat duration exactly matches this rule's threshold
      if chat_duration_seconds == rule.threshold_seconds
        # Calculate how many coins we can actually deduct
        available_coins = user.coin_balance - total_deducted
        coins_to_deduct = [available_coins, rule.coins].min

        if coins_to_deduct > MINIMUM_COIN_BALANCE
          total_deducted += coins_to_deduct
          applied_rules << {
            threshold: rule.threshold_seconds,
            coins: coins_to_deduct,
            rule_name: rule.name
          }
        else
          break
        end
      end
    end

    if total_deducted > 0
      # Ensure user never goes below the minimum coin balance
      final_balance = [user.coin_balance - total_deducted, MINIMUM_COIN_BALANCE].max
      actual_deducted = user.coin_balance - final_balance

      user.update!(coin_balance: final_balance)

      return {
        success: true,
        deducted: actual_deducted,
        new_balance: final_balance,
        applied_rules: applied_rules,
        chat_duration: chat_duration_seconds
      }
    else
      return { success: true, deducted: 0, new_balance: user.coin_balance, applied_rules: [] }
    end

  rescue => e
    return { success: false, error: e.message }
  end

  def self.get_user_balance(user_id)
    user = User.find(user_id)
    return { success: true, balance: user.coin_balance }
  rescue => e
    return { success: false, error: e.message }
  end

  def self.apply_per_swipe_deduction(user_id, rule)
    user = User.find(user_id)

    # Check if user has sufficient coins
    if user.coin_balance < rule.coins
      return { success: false, deducted: 0, new_balance: user.coin_balance, error: 'Insufficient coins for swipe' }
    end

    # Apply the deduction
    new_balance = user.coin_balance - rule.coins
    user.update!(coin_balance: new_balance)

    {
      success: true,
      deducted: rule.coins,
      new_balance: new_balance,
      applied_rule: {
        id: rule.id,
        name: rule.name,
        coins: rule.coins,
        deduction_type: rule.deduction_type
      }
    }
  rescue => e
    return { success: false, deducted: 0, new_balance: user.coin_balance, error: e.message }
  end
end
