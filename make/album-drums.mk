# optional variables:
album-trim    ?= 0
album-fadein  ?= 0
album-pad     ?= 0
album-cutoff  ?= 0
album-fadeout ?= 0

gen/album/%/song-untimed.wav: audio-album.*
	mkdir -p $(@D)
	../../scripts/audioconvert $< $@ rate 44100 channels 2

gen/album/%.wav: gen/album/%-untimed.wav
	sox $< $@ \
		trim $(album-trim) \
		fade t $(album-fadein) \
		pad $(album-pad) \
		fade t 0 $(album-cutoff) $(album-fadeout)

gen/album/%/drums.wav: gen/album/%/song.wav
	sox -n $@ rate 44100 channels 2 trim 0 1
