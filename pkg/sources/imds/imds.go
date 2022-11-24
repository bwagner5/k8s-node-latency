package imds

import (
	"context"
	"fmt"
	"time"

	"github.com/aws/aws-sdk-go-v2/feature/ec2/imds"
)

var (
	Name             = "EC2 IMDS"
	DynamicDocPrefix = "/dynamic/instance-identity/document"
	RequestedTime    = fmt.Sprintf("%s/%s", DynamicDocPrefix, "requestedTime")
	PendingTime      = fmt.Sprintf("%s/%s", DynamicDocPrefix, "pendingTime")
)

type IMDSSource struct {
	imds *imds.Client
}

type IdentityDoc struct {
	PendingTime string `json:"pendingTime"`
}

type ErrMetadata struct{}

func (e ErrMetadata) Error() string {
	return "metadata error"
}

func New(imdsClient *imds.Client) *IMDSSource {
	return &IMDSSource{
		imds: imdsClient,
	}
}

func (i IMDSSource) ClearCache() {}

func (i IMDSSource) Find(search string, firstOccurrence bool) (time.Time, error) {
	ctx := context.TODO()
	identityDoc, err := i.imds.GetInstanceIdentityDocument(ctx, &imds.GetInstanceIdentityDocumentInput{})
	if err != nil {
		return time.Time{}, fmt.Errorf("unable to retrieve instance-identity document: %v %w", err, ErrMetadata{})
	}
	if err != nil {
		return time.Time{}, err
	}
	switch search {
	case PendingTime:
		return identityDoc.PendingTime, nil
	case RequestedTime:
		// requestedTime doesn't actually exist, but this is approximately right that EC2 takes about 1 second
		// to handle the API request for an instances before it goes pending.
		return identityDoc.PendingTime.Add(-1 * time.Second), nil
	}
	return time.Time{}, fmt.Errorf("metadata for path \"%s\" is not available", search)
}

func (i IMDSSource) String() string {
	return Name
}

func (i IMDSSource) Name() string {
	return Name
}
