 #include <ctype.h>
 #include <stdio.h>
 #include <stdlib.h>
 #include <unistd.h>
 #include <string.h>
int cmpqua(char *p1,char *p2);
#define LENTESTS 15
#define true 1
#define false 0
#define int32 int
#define bool int
/* 
usage 1
    gcc tcmpqua.c;a.out toto titi
usage 
    gcc tcmpqua.c;a.out 
        passe ts les tests
        resultat attendu "test Ok"
*/

int main(int argc, char *argv[])
{
    /*
    int i = 0;
    for (i = 0; i < argc; i++) {
        printf("argv[%d] = %s\n", i, argv[i]);
    } */
    char *strs[LENTESTS][2];
    int exp[LENTESTS];
    
    int i,resu = true;
    if(argc ==3) {
        printf("'%s' %s match with '%s'\n",argv[1],cmpqua(argv[1],argv[2])?"":"do not",argv[2]);
        return 0;
    }
    exp[0]=true;strs[0][0] = "titi",strs[0][1] = "titi";
    exp[1]=true;strs[1][0] = "titi",strs[1][1] = "4titi";
    exp[2]=true;strs[2][0] = "titi",strs[2][1] = "3tita";
    exp[3]=false;strs[3][0] = "titi",strs[3][1] = "3tici";
    exp[4]=true;strs[4][0] = "titi",strs[4][1] = "titi";
    exp[5]=true;strs[5][0] = "titititititititi",strs[5][1] = "16titititititititi";
    exp[6]=true;strs[6][0] = "titititititititi",strs[6][1] = "14tititititititixx";
    exp[7]=false;strs[7][0] = "titititititititi",strs[7][1] = "15tititititititixx";
    exp[8]=true;strs[8][0] = "titi",strs[8][1] = "300titi";
    exp[9]=true;strs[9][0] = "20titi",strs[9][1] = "titi";
    
    exp[10]=false;strs[10][0] = "abc",strs[10][1] = "abcd";
    exp[11]=false;strs[11][0] = "abcdef",strs[11][1] = "abcd";
    exp[12]=true;strs[12][0] = "abcdef",strs[12][1] = "4abcd";
    exp[13]=true;strs[13][0] = "abcdef",strs[13][1] = "3abcx";
    exp[14]=true;strs[14][0] = "abcdef",strs[14][1] = "5abcd";
    
    for (i=0;i<LENTESTS;i++)
        
        if(cmpqua(strs[i][0],strs[i][1]) != exp[i]) {
            printf("test Ko: expected %s prov '%s' %s requ '%s'\n",exp[i]?"=":"!=",strs[i][0],cmpqua(strs[i][0],strs[i][1])?"=":"!=",strs[i][1]);
            resu = false;
        }
    if(resu) printf ("test Ok\n");
    return 0;
    
}

#define IDEMTXT(a,lena,b,lenb,res) \
do { \
	if(lena != lenb) res = false; \
	else { \
		if(memcmp(a,b,lena) == 0) res = true; \
		else res = false; \
	} \
} while(0)

#define GETPREFIX(rk,ra,rlen) \
do { \
	rk = 0; \
	while(rlen > 0) { \
	    if ('0' <= *ra && *ra <= '9' ) { \
            rk *=10; \
            rk += (int32)(*ra -'0'); \
            ra +=1; rlen -=1; \
	    } else break; \
	} ; \
} while(0)

bool cmpqua(char *prov,char *requ) {
	bool _res = true;
	char *_pv = prov;
	char *_pu = requ;
	int32 _lv = strlen(prov);
	int32 _lu = strlen(requ);
	int32 _rku,_rkv,_l;
	
	_l = (_lu < _lv)?_lu:_lv;
    if(_l <1) {
		printf("quality too short");
		return false;
    }  
    //printf ("'%s' %i '%s' %i\n",_pu,_lu,_pv,_lv);
    
    // required
    GETPREFIX(_rku,_pu,_lu);
    if(_lu == 0) // cath all
        return true;
        
    if(_rku > _lu) // _rku too long
        _rku = _lu;
        
    //printf ("required '%s' %i %i\n",_pu,_lu,_rku); 
       
    // provided
    GETPREFIX(_rkv,_pv,_lv);
    if(_lv == 0) // provide nothing 
        return false;
    //printf ("provided '%s' %i\n",_pv,_lv);
    
    if(_rku != 0 && _rku < _lv) {// limit comparison length
        _lv = _rku;
        _lu = _rku;
    }
    //printf ("_pu '%s' _lu %i _pv %s _lv %i\n",_pu,_lu,_pv,_lv);
    IDEMTXT(_pu,_lu,_pv,_lv,_res);
    return _res;
}

