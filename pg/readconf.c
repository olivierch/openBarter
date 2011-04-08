/*
 * readconf.c
 *
 *  Created on: 20 févr. 2011
 *      Author: olivier
 */

static void
set_null_conf(void)
{
	FILE	   *conf_file;
	char	   *path;

	path = palloc(strlen(pg_data) + 17);
	sprintf(path, "%s/openbarter.conf", pg_data);
	conf_file = fopen(path, PG_BINARY_W);
	if (conf_file == NULL)
	{
		fprintf(stderr, _("%s: could not open file \"%s\" for writing: %s\n"),
				progname, path, strerror(errno));
		exit_nicely();
	}
	if (fclose(conf_file))
	{
		fprintf(stderr, _("%s: could not write file \"%s\": %s\n"),
				progname, path, strerror(errno));
		exit_nicely();
	}
	pfree(path);
}

