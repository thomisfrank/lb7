# AI Opponent Documentation

## Overview
The AI opponent uses a rule-based decision-making system with three difficulty levels: Easy, Medium, and Hard.

## Features

### Difficulty Levels

#### EASY
- **Strategy**: Random decisions with basic awareness
- **Pass Rate**: 40% chance to pass randomly
- **Swap Accuracy**: 50% chance to pick the lowest card
- **Best For**: Beginners, testing, casual play

#### MEDIUM (Default)
- **Strategy**: Strategic play with 20% mistake rate
- **Card Priority**: 
  - Plays Draw cards with value ≥ 8
  - Plays Swap cards with value ≥ 7
  - Passes if hand value is ≤ 20 with actions remaining
- **Swap Accuracy**: 70% chance to pick the lowest card
- **Best For**: Standard gameplay, balanced challenge

#### HARD
- **Strategy**: Optimal play with only 5% mistakes
- **Decision Making**: 
  - Evaluates expected value of each action
  - Calculates hand improvement potential
  - Passes when improvement is minimal (< 2 points)
  - Passes when hand is excellent (≤ 16 points)
- **Swap Accuracy**: 90% chance to pick the lowest card
- **Best For**: Experienced players, maximum challenge

## Changing Difficulty

### In Code
Edit `round_manager.gd`, in the `_initialize_ai()` function:

```gdscript
# Change this line to set difficulty:
ai_opponent.set_difficulty(AIOpponent.Difficulty.EASY)    # Easy mode
ai_opponent.set_difficulty(AIOpponent.Difficulty.MEDIUM)  # Medium mode
ai_opponent.set_difficulty(AIOpponent.Difficulty.HARD)    # Hard mode
```

### Dynamic Difficulty (Future Enhancement)
You can add difficulty selection to your UI by:
1. Adding buttons in the menu screen
2. Storing the difficulty preference
3. Setting it in `_initialize_ai()` based on player choice

## How the AI Works

### Decision Process
1. **Calculate Hand Value**: Sum all card values
2. **Evaluate Options**: Check available Draw and Swap cards
3. **Strategic Logic**:
   - Prioritize high-value effect cards (Draw/Swap with values 7-10)
   - Consider deck state (cards remaining)
   - Evaluate expected improvement
   - Decide to play card or pass

### Card Evaluation
- **Draw Cards**: Evaluates whether drawing will improve hand (removes high card, adds average ~6.5)
- **Swap Cards**: Estimates benefit of swapping high card for player's low card
- **Pass**: Chosen when hand is already good or improvement is minimal

### Swap Target Selection
- AI tries to identify the lowest-value card in player's hand
- Success rate varies by difficulty (50% Easy, 70% Medium, 90% Hard)
- Simulates educated guessing (AI doesn't "see" player cards perfectly)

## Customization Tips

### Making AI Easier
```gdscript
# Increase pass rate in _decide_easy()
if randf() < 0.6:  # Was 0.4, now 60% pass rate
    return {"type": "pass"}

# Reduce swap accuracy
if randf() < 0.3:  # Was 0.5, now 30% correct
    return _find_lowest_card(player_hand)
```

### Making AI Harder
```gdscript
# Reduce mistake rate in _decide_hard()
if randf() < 0.01:  # Was 0.05, now only 1% mistakes
    return _decide_medium(actions_remaining)

# Improve swap accuracy to 100%
func choose_swap_target() -> Card:
    return _find_lowest_card(player_hand)  # Always picks best
```

### Adding Personality Styles

You can create different AI personalities by modifying the decision thresholds:

**Aggressive AI** (always plays cards):
```gdscript
func _decide_aggressive(actions_remaining: int) -> Dictionary:
    # Never pass unless no cards
    if opponent_hand.get_card_count() == 0:
        return {"type": "pass"}
    
    var best_move = _find_best_move(actions_remaining)
    return best_move
```

**Conservative AI** (passes more often):
```gdscript
func _decide_conservative(actions_remaining: int) -> Dictionary:
    var hand_value = _calculate_hand_value(opponent_hand)
    
    # Pass if hand is decent (≤ 28)
    if hand_value <= 28:
        return {"type": "pass"}
    
    return _find_best_move(actions_remaining)
```

## Balance Considerations

### Current Balance Points
- **Pass Threshold**: 20 points (Medium), 16-24 points (Hard)
- **Draw Priority**: Cards with value ≥ 8
- **Swap Priority**: Cards with value ≥ 7
- **Expected Deck Average**: 6.5 points

### Tuning Tips
If AI is **too strong**:
- Increase mistake rates (20% → 30% for Medium)
- Lower swap accuracy (70% → 60% for Medium)
- Raise pass thresholds (hand value 20 → 24)

If AI is **too weak**:
- Decrease mistake rates (20% → 10% for Medium)
- Increase swap accuracy (70% → 80% for Medium)
- Lower pass thresholds (hand value 20 → 16)

## Future Enhancements

### Card Counting
Track played cards to improve deck average estimation:
```gdscript
var played_cards: Array = []

func _estimate_deck_average() -> float:
    # Calculate actual average from remaining deck
    var total_possible = 0
    var count = 0
    for value in [2,3,4,5,6,7,8,9,10,11,12,13]:
        if not value in played_cards:
            total_possible += value
            count += 1
    return total_possible / float(count) if count > 0 else 6.5
```

### Learning AI
Store results of decisions to improve over time:
```gdscript
var move_history: Array = []  # Track {move, outcome}

func _learn_from_round(won: bool) -> void:
    # Adjust strategy based on results
    pass
```

### Adaptive Difficulty
Adjust difficulty based on player performance:
```gdscript
var player_win_streak: int = 0

func _adjust_difficulty() -> void:
    if player_win_streak >= 3:
        set_difficulty(Difficulty.HARD)
    elif player_win_streak <= -3:
        set_difficulty(Difficulty.EASY)
```

## Troubleshooting

### AI Not Making Moves
- Check that `opponent_hand`, `deck`, and `discard_pile` are properly initialized
- Verify EffectsManager is available at `/root/EffectsManager` or `/root/Main/EffectsManager`
- Enable debug logging to see AI decisions

### AI Making Poor Decisions
- Verify card values are being read correctly (`card.value` property)
- Check that `_calculate_hand_value()` returns correct totals
- Test with different difficulty levels

### Swap Not Working
- Ensure `player_hand` reference is set correctly
- Verify `choose_swap_target()` returns valid cards
- Check EffectsManager swap implementation

## Testing Commands

Add these to your debug keys for testing:
```gdscript
# In main.gd or round_manager.gd
func _input(event):
    if event is InputEventKey and event.pressed:
        match event.keycode:
            KEY_1:
                ai_opponent.set_difficulty(AIOpponent.Difficulty.EASY)
            KEY_2:
                ai_opponent.set_difficulty(AIOpponent.Difficulty.MEDIUM)
            KEY_3:
                ai_opponent.set_difficulty(AIOpponent.Difficulty.HARD)
            KEY_I:
                # Print AI info
                print("AI Hand Value: ", ai_opponent._calculate_hand_value(opponent_hand))
                print("Player Hand Value: ", ai_opponent._calculate_hand_value(player_hand))
```
