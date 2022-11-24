package awsnode

import (
	"regexp"
	"time"

	"github.com/bwagner5/k8s-node-latency/pkg/sources"
)

var (
	Name            = "aws-node"
	DefaultPath     = "/var/log/pods/kube-system_aws-node-*/aws-node/*.log"
	TimestampFormat = regexp.MustCompile(`[0-9]{4}\-[0-9]{2}\-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+Z`)
	TimestampLayout = "2006-01-02T15:04:05.999999999Z"
)

type AWSNodeSource struct {
	logReader *sources.LogReader
}

func New(path string) *AWSNodeSource {
	return &AWSNodeSource{
		logReader: &sources.LogReader{
			Path:            path,
			Glob:            true,
			TimestampRegex:  TimestampFormat,
			TimestampLayout: TimestampLayout,
		},
	}
}

func (a AWSNodeSource) ClearCache() {
	a.logReader.ClearCache()
}

func (a AWSNodeSource) Find(search string, firstOccurrence bool) (time.Time, error) {
	re, err := regexp.Compile(search)
	if err != nil {
		return time.Time{}, err
	}
	return a.logReader.Find(re, firstOccurrence)
}

func (a AWSNodeSource) String() string {
	return a.logReader.Path
}

func (a AWSNodeSource) Name() string {
	return Name
}
