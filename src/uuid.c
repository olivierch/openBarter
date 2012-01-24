/*
EXAMPLE
        CC      = cc
        CFLAGS  = -O `uuid-config --cflags`
        LDFLAGS = `uuid-config --ldflags`
        LIBS    = -lm `uuid-config --libs`

        all: foo
        foo: foo.o
            $(CC) $(LDFLAGS) -o foo foo.o $(LIBS)
        foo.o: foo.c
            $(CC) $(CFLAGS) -c foo.c
pour le test:
gcc `uuid-config --cflags` -lm `uuid-config --libs` uuid.c
*/
#include "stdio.h"
#include "uuid.h"
char *uuid_v1(void);
char *uuid_v3(const char *url);

main() {
	char *str;

	str = uuid_v1(); // 36 chars
	printf("V1 UUID:	%s\n",str);
	free(str);
	str = uuid_v3("openbarter.org");
	printf("V3 UUID:	%s\n",str);
	
	free(str);
}

        /* generate a DCE 1.1 v1 UUID from system environment */
        char *uuid_v1(void)
        {
            uuid_t *uuid;
            char *str;

            uuid_create(&uuid);
            uuid_make(uuid, UUID_MAKE_V1);
            str = NULL;
            uuid_export(uuid, UUID_FMT_STR, &str, NULL);
            uuid_destroy(uuid);
            return str;
        }



        /* generate a DCE 1.1 v3 UUID from an URL */
        char *uuid_v3(const char *url)
        {
            uuid_t *uuid;
            uuid_t *uuid_ns;
            char *str;

            uuid_create(&uuid);
            uuid_create(&uuid_ns);
            uuid_load(uuid_ns, "ns:URL");
            uuid_make(uuid, UUID_MAKE_V3, uuid_ns, url);
            str = NULL;
            uuid_export(uuid, UUID_FMT_STR, &str, NULL);
            uuid_destroy(uuid_ns);
            uuid_destroy(uuid);
            return str;
        }
