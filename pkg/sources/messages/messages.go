package messages

import (
	"regexp"
	"time"

	"github.com/bwagner5/k8s-node-latency/pkg/sources"
)

var (
	Name            = "Messages"
	DefaultPath     = "/var/log/messages*"
	TimestampFormat = regexp.MustCompile(`[A-Z][a-z]+[ ]+[0-9][0-9]? [0-9]{2}:[0-9]{2}:[0-9]{2}`)
	TimestampLayout = "Jan 2 15:04:05 2006"
)

type MessagesSource struct {
	logReader *sources.LogReader
}

func New(path string) *MessagesSource {
	return &MessagesSource{
		logReader: &sources.LogReader{
			Path:            path,
			Glob:            true,
			TimestampRegex:  TimestampFormat,
			TimestampLayout: TimestampLayout,
		},
	}
}

func (m MessagesSource) ClearCache() {
	m.logReader.ClearCache()
}

func (m MessagesSource) Find(search string, firstOccurrence bool) (time.Time, error) {
	re, err := regexp.Compile(search)
	if err != nil {
		return time.Time{}, err
	}
	return m.logReader.Find(re, firstOccurrence)
}

func (m MessagesSource) String() string {
	return m.logReader.Path
}

func (m MessagesSource) Name() string {
	return Name
}
