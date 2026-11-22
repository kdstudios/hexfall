import 'package:flutter_test/flutter_test.dart';
import 'package:hexfall/core/planet/planet_environment.dart';
import 'package:hexfall/render/sky_assets.dart';
import 'package:hexfall/render/sky_view.dart';

void main() {
  test('every world gets a valid sky recipe', () {
    for (final env in PlanetEnvironment.values) {
      for (var seed = 0; seed < 200; seed += 7) {
        final r = SkyRecipe.forWorld(env, seed);
        expect(r.nebula, inInclusiveRange(0, SkyAssets.nebulaCount - 1));
        expect(r.giant, inInclusiveRange(0, SkyAssets.giantCount - 1));
        expect(r.stars, inInclusiveRange(0, SkyAssets.starCount - 1));
        if (r.ring != null) expect(r.ring, inInclusiveRange(0, SkyAssets.ringCount - 1));
        expect(r.giantPos.dx, inInclusiveRange(0.05, 0.95));
        expect(r.giantPos.dy, inInclusiveRange(0.05, 0.5));
      }
    }
  });
}
