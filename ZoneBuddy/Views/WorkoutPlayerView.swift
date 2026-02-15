import SwiftUI

struct WorkoutPlayerView: View {
    @State private var viewModel: WorkoutPlayerViewModel
    @Environment(\.dismiss) private var dismiss

    let workoutName: String

    init(intervals: [Interval], workoutName: String, transitionWarningDuration: Int = 10) {
        self.workoutName = workoutName
        _viewModel = State(initialValue: WorkoutPlayerViewModel(
            intervals: intervals,
            timerProvider: LiveTimerProvider(),
            workoutName: workoutName,
            transitionWarningDuration: transitionWarningDuration
        ))
    }

    var body: some View {
        ZStack {
            viewModel.currentZoneColor
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: viewModel.currentIntervalIndex)

            if viewModel.isFinished {
                finishedOverlay
            } else {
                activeWorkoutOverlay
            }

            VStack {
                Spacer()
                if viewModel.showTransitionBanner {
                    TransitionBannerView(
                        upcomingLabel: viewModel.upcomingLabel,
                        upcomingColor: viewModel.upcomingZoneColor
                    )
                    .transition(.opacity)
                    .padding(.bottom, 100)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: viewModel.showTransitionBanner)
            .allowsHitTesting(false)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            viewModel.start()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            viewModel.pause()
        }
        .onTapGesture {
            viewModel.showTimer.toggle()
        }
    }

    private var activeWorkoutOverlay: some View {
        VStack(spacing: 20) {
            Text(workoutName)
                .font(.title3)
                .foregroundStyle(viewModel.currentForegroundColor.opacity(0.7))

            Spacer()

            Text(viewModel.currentLabel)
                .font(.title)
                .fontWeight(.medium)
                .foregroundStyle(viewModel.currentForegroundColor)

            if let zoneNumber = viewModel.currentZoneNumber {
                Text("\(zoneNumber)")
                    .font(.system(size: 200, weight: .bold, design: .rounded))
                    .foregroundStyle(viewModel.currentForegroundColor)
                    .contentTransition(.numericText())
            } else {
                Image(systemName: "flame.fill")
                    .font(.system(size: 120))
                    .foregroundStyle(viewModel.currentForegroundColor)
            }

            if viewModel.showTimer {
                Text(viewModel.secondsRemaining.formattedDuration)
                    .font(.system(size: 60, weight: .light, design: .monospaced))
                    .foregroundStyle(viewModel.currentForegroundColor)
                    .contentTransition(.numericText())
            }

            Spacer()

            HStack(spacing: 40) {
                Button {
                    viewModel.pause()
                    viewModel.endActivity()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(viewModel.currentForegroundColor.opacity(0.6))
                }

                Button {
                    viewModel.togglePlayPause()
                } label: {
                    Image(systemName: viewModel.isRunning ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(viewModel.currentForegroundColor.opacity(0.6))
                }

                Button {
                    viewModel.audioCuesEnabled.toggle()
                } label: {
                    Image(systemName: viewModel.audioCuesEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(viewModel.currentForegroundColor.opacity(0.6))
                }
            }
            .padding(.bottom, 20)
        }
        .padding()
    }

    private var finishedOverlay: some View {
        VStack(spacing: 30) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.white)

            Text("Workout Complete!")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            Text("Total time: \(viewModel.totalElapsedSeconds.formattedDuration)")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.8))

            Button("Done") {
                viewModel.endActivity()
                dismiss()
            }
            .font(.title3)
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .padding(.top, 20)
        }
    }
}

#Preview {
    NavigationStack {
        WorkoutPlayerView(
            intervals: [
                Interval(zone: .zone2, duration: 15, sortOrder: 0),
                Interval(zone: .zone4, duration: 10, sortOrder: 1),
                Interval(zone: .zone1, duration: 10, sortOrder: 2),
            ],
            workoutName: "Preview Ride"
        )
    }
}
