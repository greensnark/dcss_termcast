
.c.o:
	gcc -Wall -c $<

all:	ttrtail

ttrtail: ttrtail.o
	gcc -o $@ $<

clean:
	rm -f *.o ttrtail
