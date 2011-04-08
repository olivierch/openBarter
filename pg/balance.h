#ifndef defined__balance_h
#define defined__balance_h
// struct ob_ConnectDesc defined in openbarter.h

typedef struct ob_ConnectDesc *ob_tConnectDescp;

ob_tConnectDescp ob_balance_getBestConnect(void);

int ob_balance_recordStat(ob_tConnectDescp,TimestampTz);
int ob_balance_invalidConnect(ob_tConnectDescp);
void ob_balance_free_connect(ob_tConnectDescp);
void ob_balance_testtabconnect(void);

/* stratégie de load balancing
Lorsque le maitre appelle une fonction spéciale ob_getdraft_from_master(), il fait le choix de la meilleure copie.
la commande ob_getdraft_get() est reçue sur la copie, doit être exécutée, puis retourner les infos au maitre,
le maitre reçoit les résultats de la copie et les exploite.

si aucune copie n'existe, on exécute ob_getdraft_get() sur le maitre.

*/

#endif
