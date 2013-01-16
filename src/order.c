
typedef struct Torder {
	int32	vl_len_;
	int64	qtt_prov,qtt_requ,qtt;
	int32	id;
	uint32  off_own,off_tsvector,off_stquery;
} Torder;

initialiser l'entete

insérer un bloc variable
repalloc
obtenir l'offset libre avec vl_len_
copier le bloc variable
définir l'offset du bloc variable
mettre à jour vl_len_

