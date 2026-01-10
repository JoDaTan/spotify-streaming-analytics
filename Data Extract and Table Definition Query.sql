CREATE TABLE IF NOT EXISTS raw_spotify_history(
	id SERIAL PRIMARY KEY,
	data JSONB
);

/*
TABLE CREATION WITH DATA POPULATING
Here I will implement a star schema using the streams history dataset.
The following dimensions table will be created to reduce redundancy; artists, albums, songs
And a fact table called streams (my spotify streaming history)

Under each table definition statement is a query to insert data into the table.
*/
CREATE TABLE IF NOT EXISTS artists(
	artist_id SERIAL PRIMARY KEY,
	artist_name TEXT UNIQUE
);

INSERT INTO artists(artist_name)
SELECT DISTINCT r.data ->> 'master_metadata_album_artist_name'
FROM raw_spotify_history r
WHERE r.data ->> 'master_metadata_album_artist_name' IS NOT NULL
ON CONFLICT (artist_name) DO NOTHING;


CREATE TABLE IF NOT EXISTS albums(
	album_id SERIAL PRIMARY KEY,
	album_title TEXT,
	album_artist INT REFERENCES artists(artist_id),
	UNIQUE(album_title, album_artist)
);

INSERT INTO albums(album_title, album_artist)
SELECT DISTINCT 
	COALESCE(r.data ->> 'master_metadata_album_album_name', r.data ->> 'episode_show_name'),
	a.artist_id
FROM raw_spotify_history r
JOIN artists a
ON r.data ->> 'master_metadata_album_artist_name' = a.artist_name
WHERE COALESCE(r.data ->> 'master_metadata_album_album_name', r.data ->> 'episode_show_name') IS NOT NULL
ON CONFLICT (album_title, album_artist) DO NOTHING;


CREATE TABLE IF NOT EXISTS songs(
	song_id SERIAL PRIMARY KEY,
	song_title TEXT,
	song_uri TEXT UNIQUE,
	artist_id INT REFERENCES artists(artist_id),
	album_id INT REFERENCES albums(album_id),
	song_type TEXT CHECK (song_type IN ('track', 'podcast', 'audiobook'))
);

INSERT INTO songs(song_title, song_uri, artist_id, album_id, song_type)
SELECT DISTINCT 
	COALESCE ( -- Returns the value of the first non-null column as the song_title
		r.data ->> 'master_metadata_track_name', 
		r.data ->> 'audiobook_chapter_title', 
		r.data ->> 'episode_name'
	) AS song_title,
	COALESCE( -- Returns the value of the first non-null column as the uri for the song
		r.data ->> 'spotify_track_uri', 
		r.data ->> 'spotify_episode_uri', 
		r.data ->> 'audiobook_chapter_uri'
	) AS song_uri,
	ar.artist_id,
	al.album_id,
	CASE
		WHEN r.data ->> 'spotify_track_uri' IS NOT NULL THEN 'track'
		WHEN r.data ->> 'spotify_episode_uri' IS NOT NULL THEN 'podcast'
		WHEN r.data ->> 'audiobook_chapter_uri' IS NOT NULL THEN 'audiobook'
	END AS song_type
FROM raw_spotify_history r
LEFT JOIN artists ar
	ON ar.artist_name = r.data ->> 'master_metadata_album_artist_name'		
LEFT JOIN albums al
	ON al.album_title = COALESCE(
		r.data ->> 'master_metadata_album_album_name', 
		r.data ->> 'episode_show_name'
	)
WHERE COALESCE ( 
	r.data ->> 'master_metadata_track_name', 
	r.data ->> 'audiobook_chapter_title', 
	r.data ->> 'episode_name'
) IS NOT NULL
ON CONFLICT (song_uri) DO NOTHING;


CREATE TABLE streams(
	stream_id SERIAL PRIMARY KEY,
	song_id INT REFERENCES songs(song_id),
	stream_time TIMESTAMPTZ,
	play_length_ms INT,
	platform TEXT,
	shuffle BOOLEAN,
	skipped BOOLEAN,
	offline BOOLEAN,
	country_code VARCHAR(5),
	reason_start TEXT,
	reason_end TEXT
);

INSERT INTO streams(
	song_id, stream_time, play_length_ms, platform, shuffle, skipped, offline, country_code, reason_start, reason_end
)
SELECT
	s.song_id, 
	(r.data ->> 'ts')::TIMESTAMPTZ,
	(r.data ->> 'ms_played')::INT,
	r.data ->> 'platform',
	(r.data ->> 'shuffle')::BOOLEAN,
	(r.data ->> 'skipped')::BOOLEAN,
	(r.data ->> 'offline')::BOOLEAN,
	r.data ->> 'conn_country',
	r.data ->> 'reason_start',
	r.data ->> 'reason_end'
FROM raw_spotify_history r
JOIN songs s
	ON s.song_uri = COALESCE(
		r.data ->> 'spotify_track_uri',
		r.data ->> 'spotify_episode_uri',
		r.data ->> 'audiobook_chapter_uri'
	);
