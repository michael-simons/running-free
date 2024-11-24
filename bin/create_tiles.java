///usr/bin/env jbang "$0" "$@" ; exit $?
//JAVA 23
//DEPS info.picocli:picocli:4.7.6
//DEPS org.duckdb:duckdb_jdbc:1.1.3
import java.io.FileInputStream;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.Callable;
import java.util.function.Function;
import java.util.stream.Collectors;
import java.util.zip.GZIPInputStream;

import picocli.AutoComplete;
import picocli.CommandLine;
import picocli.CommandLine.ExitCode;

@SuppressWarnings( {"SqlDialectInspection", "SqlNoDataSourceInspection"})
@CommandLine.Command(
	name = "create-tiles",
	mixinStandardHelpOptions = true,
	description = "Processes new Garmin activities, (re)visits tiles and updates the clusters.",
	subcommands = {
		AutoComplete.GenerateCompletion.class,
		CommandLine.HelpCommand.class
	}
)
public class create_tiles implements Callable<Integer> {

	@CommandLine.Option(names = "--tracks-dir", required = true, defaultValue = "Garmin/Tracks")
	private Path tracksDir;

	@CommandLine.Parameters(arity = "1")
	private Path database;

	public static void main(String[] args) {
		int exitCode = new CommandLine(new create_tiles()).execute(args);
		System.exit(exitCode);
	}

	@Override
	public Integer call() throws Exception {

		var userDirectory = Path.of(System.getProperty("user.dir"));
		tracksDir = userDirectory.resolve(tracksDir);
		if (!Files.isDirectory(tracksDir)) {
			System.err.println("Directory containing tracks not found: " + tracksDir);
			return ExitCode.USAGE;
		}

		database = userDirectory.resolve(database);
		if (!Files.isRegularFile(database)) {
			System.err.println("Database not found: " + database);
			return ExitCode.USAGE;
		}

		try (var tiles = Tiles.of(tracksDir, database)) {
			tiles.update();
		}

		return ExitCode.OK;
	}

	static class Tiles implements AutoCloseable {

		record IdAndPath(Long id, Path path) {
		}

		record Tile(long x, long y, int zoom) {
		}

		private final static int[] DX = {1, 0, -1, 0};
		private final static int[] DY = {0, 1, 0, -1};

		private final Map<String, Path> allGpxFiles;

		private final Connection connection;

		static Tiles of(Path tracksDir, Path database) throws IOException, SQLException {
			try (
				var allFiles = Files.list(tracksDir);
			) {
				var allGpxFiles = allFiles
					.filter(p -> p.getFileName().toString().endsWith(".gpx.gz"))
					.collect(Collectors.toMap(p -> p.getFileName().toString(), Function.identity()));

				var connection = DriverManager.getConnection("jdbc:duckdb:" + database.toAbsolutePath());
				connection.setAutoCommit(false);
				try (
					var stmt = connection.createStatement();
				) {
					stmt.execute("INSTALL spatial");
					stmt.execute("LOAD spatial");
				}
				return new Tiles(allGpxFiles, connection);
			}
		}

		private Tiles(Map<String, Path> allGpxFiles, Connection connection) {
			this.allGpxFiles = allGpxFiles;
			this.connection = connection;
		}

		public void update() throws Exception {
			this.processNewActivities();
			this.labelCluster();
		}

		@Override
		public void close() throws Exception {
			if (this.connection != null) {
				this.connection.close();
			}
		}

		private void processNewActivities() throws SQLException, IOException {

			var files = findUnprocessedActivities();
			var query = """
				WITH meta AS (
				    SELECT ? AS zoom, ? AS garmin_id
				),
				new_tiles AS (
				    SELECT DISTINCT meta.garmin_id, f_get_tile_number(geom, meta.zoom) AS tile
				    FROM st_read(?, layer = 'track_points'), meta
				)
				INSERT INTO tiles BY NAME
				SELECT tile.x,
				       tile.y,
				       tile.zoom,
				       f_make_tile(tile) AS geom,
				       1 AS visited_count,
				       started_on::date AS visited_first_on,
				       started_on::date AS visited_last_on,
				FROM new_tiles JOIN garmin_activities USING(garmin_id)
				ON CONFLICT DO UPDATE SET
				    visited_count = visited_count + 1,
				    visited_first_on = least(visited_first_on, excluded.visited_first_on),
				    visited_last_on = greatest(visited_last_on, excluded.visited_last_on);
				""";

			// Create or update tiles
			var tmpFiles = new ArrayList<Path>();
			try {
				try (var stmt = connection.prepareStatement(query)) {
					for (var file : files) {
						var tmp = Files.createTempFile("create-tiles-", ".gpx");
						try (var gis = new GZIPInputStream(new FileInputStream(file.path().toFile()))) {
							Files.copy(gis, tmp, StandardCopyOption.REPLACE_EXISTING);
						}
						stmt.setInt(1, 14);
						stmt.setLong(2, file.id());
						stmt.setString(3, tmp.toString());
						tmpFiles.add(tmp);
						stmt.addBatch();
					}
					stmt.executeBatch();
				}

				// Mark activities as processed
				try (var stmt = connection.prepareStatement("UPDATE garmin_activities SET gpx_processed = true WHERE garmin_id = ?")) {
					for (var file : files) {
						stmt.setLong(1, file.id());
						stmt.addBatch();
					}
					stmt.executeBatch();
				}
				connection.commit();
			} finally {
				for (Path tmpFile : tmpFiles) {
					Files.deleteIfExists(tmpFile);
				}
			}
		}

		private Set<IdAndPath> findUnprocessedActivities() throws SQLException {
			try (
				var stmt = connection.createStatement();
				var result = stmt.executeQuery("""
					SELECT garmin_id
					FROM garmin_activities
					WHERE gpx_available AND NOT gpx_processed
					ORDER BY started_on DESC""")
			) {
				var unprocessedActivities = new HashSet<IdAndPath>();
				while (result.next()) {
					var id = result.getLong(1);
					var path = allGpxFiles.get(id + ".gpx.gz");
					if (path != null) {
						unprocessedActivities.add(new IdAndPath(id, path));
					}
				}
				return unprocessedActivities;
			}
		}

		private void labelCluster() throws SQLException {

			var tiles = new LinkedHashSet<Tile>();
			try (var stmt = connection.prepareStatement("SELECT x, y, zoom FROM tiles WHERE zoom = ? ORDER BY x, y");
			) {
				stmt.setLong(1, 14);
				try (var result = stmt.executeQuery()) {
					while (result.next()) {
						tiles.add(new Tile(result.getLong("x"), result.getLong("y"), result.getInt("zoom")));
					}
				}
			}
			var labels = doLabel(tiles);
			try (
				var stmt = connection.prepareStatement("UPDATE tiles SET CLUSTER = ? WHERE x = ? AND y = ? AND zoom = ?");
			) {
				for (Tile tile : tiles) {
					stmt.setInt(1, labels.getOrDefault(tile, 0));
					stmt.setLong(2, tile.x());
					stmt.setLong(3, tile.y());
					stmt.setLong(4, tile.zoom());
					stmt.addBatch();
				}
				stmt.executeBatch();
			}
			connection.commit();
		}

		/**
		 * Depth first search implementation of "one component at a time",
		 * see<a href=" https://en.wikipedia.org/wiki/Connected-component_labeling#cite_note-1">...</a>5
		 *
		 * @param tiles the tiles to be labelled
		 * @return the new labels
		 */
		private static Map<Tile, Integer> doLabel(LinkedHashSet<Tile> tiles) {
			int label = 0;
			var labels = new HashMap<Tile, Integer>();

			for (var tile : tiles) {
				if (!labels.containsKey(tile)) {
					dfs(tiles, labels, tile, ++label);
				}
			}
			return labels;
		}

		private static void dfs(LinkedHashSet<Tile> tiles, Map<Tile, Integer> labels, Tile currentTile, int currentLabel) {
			// already labeled or not touched
			if (labels.containsKey(currentTile) || !tiles.contains(currentTile)) {
				return;
			}

			// Check all for borders before marking (https://en.wikipedia.org/wiki/Pixel_connectivity) before including this tile
			for (int direction = 0; direction < 4; ++direction) {
				if (!tiles.contains(new Tile(currentTile.x() + DX[direction], currentTile.y() + DY[direction], currentTile.zoom()))) {
					return;
				}
			}

			// mark the tile
			labels.put(currentTile, currentLabel);

			// recursively mark the neighbors
			for (int direction = 0; direction < 4; ++direction) {
				dfs(tiles, labels, new Tile(currentTile.x() + DX[direction], currentTile.y() + DY[direction], currentTile.zoom()), currentLabel);
			}
		}
	}
}
