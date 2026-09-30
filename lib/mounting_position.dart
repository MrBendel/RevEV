/// Physical phone positions for comparing test sessions. These are not sensor
/// coordinate transforms: motion control and calibration are not implemented.
enum MountingPosition {
  trayTopForward(
    'Tray · top toward dashboard',
    'Screen up; charging port toward the seats. A slight tray tilt is fine.',
  ),
  trayTopRearward(
    'Tray · top toward seats',
    'Screen up; charging port toward the dashboard.',
  ),
  trayTopLeft(
    'Tray · top toward left door',
    'Screen up, sideways. Left is as seen sitting in the car facing forward.',
  ),
  trayTopRight(
    'Tray · top toward right door',
    'Screen up, sideways. Right is as seen sitting in the car facing forward.',
  ),
  uprightPortrait(
    'Upright · portrait',
    'Screen toward the seats; top edge up and charging port down.',
  ),
  uprightLandscapeLeft(
    'Upright · top toward left door',
    'Screen toward the seats, sideways; charging port toward the right door.',
  ),
  uprightLandscapeRight(
    'Upright · top toward right door',
    'Screen toward the seats, sideways; charging port toward the left door.',
  );

  const MountingPosition(this.label, this.description);
  final String label;
  final String description;
}
