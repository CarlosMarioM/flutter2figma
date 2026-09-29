import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Bloc-driven UI, as found in real apps: everything shown depends on the
/// cubit's state. flutter2figma exports the initial state.
class ScoreboardScreen extends StatelessWidget {
  const ScoreboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ScoreCubit(),
      child: BlocBuilder<ScoreCubit, ScoreState>(
        builder: (context, state) {
          if (state.error != null) {
            return Scaffold(body: Center(child: Text(state.error!)));
          }
          return Scaffold(
            appBar: AppBar(title: Text('Round ${state.round}')),
            body: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${state.player}: ${state.score}'),
                    Switch(value: state.autoPlay, onChanged: (_) {}),
                  ],
                ),
                const _Board(),
                Checkbox(value: state.hints, onChanged: (_) {}),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Board extends StatelessWidget {
  const _Board();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ScoreCubit, ScoreState>(
      // An Expanded behind a project widget and a BlocBuilder.
      builder: (context, state) => Expanded(
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
          ),
          itemCount: state.cells.length,
          itemBuilder: (context, index) => const Card(child: SizedBox()),
        ),
      ),
    );
  }
}

class ScoreCubit extends Cubit<ScoreState> {
  ScoreCubit() : super(const ScoreState(player: 'Ada'));

  void score() => emit(
    ScoreState(player: state.player, score: state.score + 1, round: 2),
  );
}

class ScoreState {
  const ScoreState({
    required this.player,
    this.score = 0,
    this.round = 1,
    this.autoPlay = false,
    this.hints = true,
    this.cells = const [0, 0, 0, 0, 0, 0],
    this.error,
  });

  final String player;
  final int score;
  final int round;
  final bool autoPlay;
  final bool hints;
  final List<int> cells;
  final String? error;
}
