DC=dmd
DFLAGS= -w -wi
ifdef DEBUG
DFLAGS += -unittest -debug -g
else
DFLAGS += -O -release
endif  
LDFLAGS=
SOURCES=midisplit.d
OBJECTS=$(SOURCES:.d=.o)
EXECUTABLE=midisplit
INSTALL_PATH=/usr/local

all: $(SOURCES) $(EXECUTABLE)

$(EXECUTABLE): $(OBJECTS) 
	$(DC) $(LDFLAGS) $(OBJECTS) -of$@

%.o:%.d
	$(DC) $(DFLAGS) -c $< -of$@

clean:
	rm -f $(EXECUTABLE) *.o

install: all
	cp $(EXECUTABLE) $(INSTALL_PATH)/bin
	#/usr/local doesn't get as populated as it did before package managers
	if [ ! -d $(INSTALL_PATH)/man/man1 ]; then mkdir -p $(INSTALL_PATH)/man/man1; fi
	cp $(EXECUTABLE).1 $(INSTALL_PATH)/man/man1/
