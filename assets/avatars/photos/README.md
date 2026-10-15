# Profile photos

Eight user-supplied JPEGs, bundled locally. `profile_avatar.dart` defines matching
square, face-focused crops with circular masks. The source photos are unchanged.
Only these eight photos are offered. Account JSON uses `avatarSet: photos-v1`;
legacy supplied photo indices 30–37 migrate to 0–7, while retired illustrated
avatar selections use the first supplied photo. Profile IDs and settings remain.
