CC      = gcc
CFLAGS  = -O2 -Wall
LDLIBS  = -lwinmm -lm
TARGET  = morse_trainer.exe

all: $(TARGET)

$(TARGET): morse_trainer.c
	$(CC) $(CFLAGS) morse_trainer.c -o $(TARGET) $(LDLIBS)

clean:
	del /Q $(TARGET) 2>NUL || rm -f $(TARGET)

.PHONY: all clean
